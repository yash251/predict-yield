// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PredictYieldMarket.sol";
import "../src/FTSOv2YieldOracle.sol";
import "../src/interfaces/IFAsset.sol";
import "../src/interfaces/IFTSOv2.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockFXRP
 * @notice Mock FXRP token for testing
 */
contract MockFXRP is ERC20 {
    uint256 public constant COLLATERAL_RATIO = 1300; // 13% in basis points
    uint256 public constant MIN_MINT_AMOUNT = 1 ether;
    bool public mintingEnabled = true;

    constructor() ERC20("Mock FXRP", "FXRP") {}

    function mint(
        uint256 amount,
        uint256 collateralAmount
    ) external returns (bool) {
        require(mintingEnabled, "Minting disabled");
        require(amount >= MIN_MINT_AMOUNT, "Below minimum");
        require(
            collateralAmount >= (amount * COLLATERAL_RATIO) / 10000,
            "Insufficient collateral"
        );

        _mint(msg.sender, amount);
        return true;
    }

    function redeem(uint256 amount) external returns (bool) {
        _burn(msg.sender, amount);
        return true;
    }

    function getCollateralRatio() external pure returns (uint256) {
        return COLLATERAL_RATIO;
    }

    function getMinMintAmount() external pure returns (uint256) {
        return MIN_MINT_AMOUNT;
    }

    function isMintingEnabled() external view returns (bool) {
        return mintingEnabled;
    }

    function setMintingEnabled(bool enabled) external {
        mintingEnabled = enabled;
    }

    // Helper function for testing
    function mintTo(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title MockFTSOv2
 * @notice Mock FTSOv2 for testing
 */
contract MockFTSOv2 is IFTSOv2Interface {
    mapping(bytes21 => uint256) public feedValues;
    mapping(bytes21 => int8) public feedDecimals;
    uint64 public currentTimestamp;

    constructor() {
        currentTimestamp = uint64(block.timestamp);

        // Initialize test feeds
        feedValues[FeedIds.USDC_USD] = 100000; // $1.00000 with 5 decimals
        feedDecimals[FeedIds.USDC_USD] = 5;
    }

    function getFeedById(
        bytes21 feedId
    ) external view returns (uint256 value, int8 decimals, uint64 timestamp) {
        return (feedValues[feedId], feedDecimals[feedId], currentTimestamp);
    }

    function getFeedByIdInWei(
        bytes21 feedId
    ) external view returns (uint256 value, uint64 timestamp) {
        uint256 feedValue = feedValues[feedId];
        value = feedValue * 1e13; // Convert from 5 decimals to 18 decimals
        return (value, currentTimestamp);
    }

    function getFeedsById(
        bytes21[] calldata feedIds
    )
        external
        view
        returns (
            uint256[] memory values,
            int8[] memory decimals,
            uint64 timestamp
        )
    {
        values = new uint256[](feedIds.length);
        decimals = new int8[](feedIds.length);

        for (uint256 i = 0; i < feedIds.length; i++) {
            values[i] = feedValues[feedIds[i]];
            decimals[i] = feedDecimals[feedIds[i]];
        }

        return (values, decimals, currentTimestamp);
    }

    function getFeedsByIdInWei(
        bytes21[] calldata feedIds
    ) external view returns (uint256[] memory values, uint64 timestamp) {
        values = new uint256[](feedIds.length);

        for (uint256 i = 0; i < feedIds.length; i++) {
            values[i] = feedValues[feedIds[i]] * 1e13;
        }

        return (values, currentTimestamp);
    }
}

/**
 * @title MockContractRegistry
 * @notice Mock contract registry for testing
 */
contract MockContractRegistry is IContractRegistry {
    IFTSOv2Interface public ftsoV2;

    constructor(address _ftsoV2) {
        ftsoV2 = IFTSOv2Interface(_ftsoV2);
    }

    function getFtsoV2() external view returns (IFTSOv2Interface) {
        return ftsoV2;
    }

    function getTestFtsoV2() external view returns (IFTSOv2Interface) {
        return ftsoV2;
    }
}

/**
 * @title PredictYieldMarketTest
 * @notice Test suite for PredictYieldMarket contract with FTSOv2 integration
 */
contract PredictYieldMarketTest is Test {
    PredictYieldMarket public market;
    FTSOv2YieldOracle public yieldOracle;
    MockFXRP public fxrp;
    MockFTSOv2 public mockFTSOv2;
    MockContractRegistry public contractRegistry;

    address public owner = address(0x1);
    address public feeRecipient = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public dataProvider = address(0x5);

    // Test constants
    uint256 constant INITIAL_FXRP_AMOUNT = 1000 ether;
    uint256 constant MIN_STAKE = 1 ether;
    uint256 constant MAX_STAKE = 1000 ether;
    string constant TEST_PROTOCOL = "AAVE_USDC";

    event MarketCreated(
        uint256 indexed marketId,
        string description,
        string protocol,
        uint256 targetYieldRate,
        uint256 endTime,
        uint256 settlementTime,
        bool autoSettlement
    );

    event BetPlaced(
        uint256 indexed betId,
        uint256 indexed marketId,
        address indexed user,
        uint256 amount,
        bool prediction
    );

    function setUp() public {
        // Deploy mocks
        fxrp = new MockFXRP();
        mockFTSOv2 = new MockFTSOv2();
        contractRegistry = new MockContractRegistry(address(mockFTSOv2));

        // Deploy yield oracle
        vm.prank(owner);
        yieldOracle = new FTSOv2YieldOracle(address(contractRegistry), owner);

        // Authorize data provider
        vm.prank(owner);
        yieldOracle.authorizeProvider(TEST_PROTOCOL, dataProvider);

        // Deploy main market contract
        vm.prank(owner);
        market = new PredictYieldMarket(
            address(fxrp),
            address(yieldOracle),
            feeRecipient,
            owner
        );

        // Mint FXRP to users for testing
        fxrp.mintTo(user1, INITIAL_FXRP_AMOUNT);
        fxrp.mintTo(user2, INITIAL_FXRP_AMOUNT);

        // Approve market contract to spend FXRP
        vm.prank(user1);
        fxrp.approve(address(market), type(uint256).max);

        vm.prank(user2);
        fxrp.approve(address(market), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testDeployment() public {
        assertEq(address(market.fxrpToken()), address(fxrp));
        assertEq(address(market.yieldOracle()), address(yieldOracle));
        assertEq(market.feeRecipient(), feeRecipient);
        assertEq(market.owner(), owner);
        assertEq(market.nextMarketId(), 1);
        assertEq(market.nextBetId(), 1);
        assertEq(market.minStakeAmount(), MIN_STAKE);
        assertEq(market.maxStakeAmount(), MAX_STAKE);
        assertEq(market.platformFee(), 100); // 1%
        assertEq(market.minConfidenceScore(), 1000); // 10%
    }

    function testDeploymentFailures() public {
        vm.expectRevert("Invalid FXRP token address");
        new PredictYieldMarket(
            address(0),
            address(yieldOracle),
            feeRecipient,
            owner
        );

        vm.expectRevert("Invalid yield oracle address");
        new PredictYieldMarket(address(fxrp), address(0), feeRecipient, owner);

        vm.expectRevert("Invalid fee recipient");
        new PredictYieldMarket(
            address(fxrp),
            address(yieldOracle),
            address(0),
            owner
        );
    }

    /*//////////////////////////////////////////////////////////////
                           MARKET CREATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testCreateMarket() public {
        string memory description = "Will Aave USDC yield exceed 4.5%?";
        uint256 targetYieldRate = 450; // 4.5%
        uint256 duration = 7 days;
        bool autoSettlement = true;

        vm.expectEmit(true, false, false, true);
        emit MarketCreated(
            1,
            description,
            TEST_PROTOCOL,
            targetYieldRate,
            block.timestamp + duration,
            block.timestamp + duration + 1 hours,
            autoSettlement
        );

        vm.prank(owner);
        uint256 marketId = market.createMarket(
            description,
            TEST_PROTOCOL,
            targetYieldRate,
            duration,
            autoSettlement
        );

        assertEq(marketId, 1);
        assertEq(market.nextMarketId(), 2);

        PredictYieldMarket.Market memory marketData = market.getMarket(1);
        assertEq(marketData.id, 1);
        assertEq(marketData.description, description);
        assertEq(marketData.protocol, TEST_PROTOCOL);
        assertEq(marketData.targetYieldRate, targetYieldRate);
        assertEq(marketData.endTime, block.timestamp + duration);
        assertEq(
            marketData.settlementTime,
            block.timestamp + duration + 1 hours
        );
        assertEq(marketData.autoSettlement, autoSettlement);
        assertEq(
            uint256(marketData.status),
            uint256(PredictYieldMarket.MarketStatus.Active)
        );
    }

    function testCreateMarketFailures() public {
        // Only owner can create markets
        vm.prank(user1);
        vm.expectRevert();
        market.createMarket("Test", TEST_PROTOCOL, 450, 7 days, false);

        vm.startPrank(owner);

        // Empty description
        vm.expectRevert("Description cannot be empty");
        market.createMarket("", TEST_PROTOCOL, 450, 7 days, false);

        // Empty protocol
        vm.expectRevert("Protocol cannot be empty");
        market.createMarket("Test", "", 450, 7 days, false);

        // Invalid yield rate
        vm.expectRevert("Invalid yield rate");
        market.createMarket("Test", TEST_PROTOCOL, 0, 7 days, false);

        vm.expectRevert("Invalid yield rate");
        market.createMarket("Test", TEST_PROTOCOL, 10001, 7 days, false);

        // Invalid duration
        vm.expectRevert("Invalid duration");
        market.createMarket("Test", TEST_PROTOCOL, 450, 30 minutes, false);

        vm.expectRevert("Invalid duration");
        market.createMarket("Test", TEST_PROTOCOL, 450, 31 days, false);

        vm.stopPrank();
    }

    function testCreateMarketWithInvalidProtocol() public {
        vm.prank(owner);
        vm.expectRevert("Protocol does not exist");
        market.createMarket("Test", "INVALID_PROTOCOL", 450, 7 days, true);
    }

    /*//////////////////////////////////////////////////////////////
                             BETTING TESTS
    //////////////////////////////////////////////////////////////*/

    function testPlaceBet() public {
        // Create market
        vm.prank(owner);
        uint256 marketId = market.createMarket(
            "Will Aave USDC yield exceed 4.5%?",
            TEST_PROTOCOL,
            450,
            7 days,
            false
        );

        uint256 betAmount = 10 ether;
        bool prediction = true; // YES

        vm.expectEmit(true, true, true, true);
        emit BetPlaced(1, marketId, user1, betAmount, prediction);

        vm.prank(user1);
        uint256 betId = market.placeBet(marketId, betAmount, prediction);

        assertEq(betId, 1);
        assertEq(market.nextBetId(), 2);

        // Check bet data
        PredictYieldMarket.Bet memory bet = market.getBet(1);
        assertEq(bet.marketId, marketId);
        assertEq(bet.user, user1);
        assertEq(bet.amount, betAmount);
        assertEq(bet.prediction, prediction);
        assertEq(bet.claimed, false);

        // Check market totals
        PredictYieldMarket.Market memory marketData = market.getMarket(
            marketId
        );
        assertEq(marketData.totalStakedYes, betAmount);
        assertEq(marketData.totalStakedNo, 0);

        // Check FXRP balance
        assertEq(fxrp.balanceOf(user1), INITIAL_FXRP_AMOUNT - betAmount);
        assertEq(fxrp.balanceOf(address(market)), betAmount);
    }

    function testPlaceBetFailures() public {
        // Create market
        vm.prank(owner);
        uint256 marketId = market.createMarket(
            "Test Market",
            TEST_PROTOCOL,
            450,
            7 days,
            false
        );

        vm.startPrank(user1);

        // Invalid market ID
        vm.expectRevert("Invalid market ID");
        market.placeBet(999, 10 ether, true);

        // Invalid stake amount
        vm.expectRevert("Invalid stake amount");
        market.placeBet(marketId, 0.5 ether, true); // Below minimum

        vm.expectRevert("Invalid stake amount");
        market.placeBet(marketId, 1001 ether, true); // Above maximum

        // Insufficient approval
        fxrp.approve(address(market), 0);
        vm.expectRevert();
        market.placeBet(marketId, 10 ether, true);

        vm.stopPrank();
    }

    function testPlaceBetAfterMarketEnd() public {
        // Create market with short duration
        vm.prank(owner);
        uint256 marketId = market.createMarket(
            "Test Market",
            TEST_PROTOCOL,
            450,
            1 hours,
            false
        );

        // Fast forward past market end
        vm.warp(block.timestamp + 2 hours);

        vm.prank(user1);
        vm.expectRevert("Market has ended");
        market.placeBet(marketId, 10 ether, true);
    }

    /*//////////////////////////////////////////////////////////////
                         MARKET SETTLEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testSettleMarket() public {
        // Create market
        vm.prank(owner);
        uint256 marketId = market.createMarket(
            "Test Market",
            TEST_PROTOCOL,
            450,
            1 hours,
            false
        );

        // Place bets
        vm.prank(user1);
        market.placeBet(marketId, 10 ether, true); // YES

        vm.prank(user2);
        market.placeBet(marketId, 15 ether, false); // NO

        // Fast forward past market end
        vm.warp(block.timestamp + 2 hours);

        // Settle market manually
        uint256 actualYieldRate = 500; // 5% > 4.5%

        vm.prank(owner);
        market.settleMarket(marketId, actualYieldRate);

        // Check market status
        PredictYieldMarket.Market memory marketData = market.getMarket(
            marketId
        );
        assertEq(marketData.actualYieldRate, actualYieldRate);
        assertEq(
            uint256(marketData.status),
            uint256(PredictYieldMarket.MarketStatus.Settled)
        );
    }

    function testAttemptAutoSettlement() public {
        // Set up yield data in oracle
        vm.prank(dataProvider);
        yieldOracle.updateYieldRate(TEST_PROTOCOL, 500); // 5%

        // Create market with auto settlement
        vm.prank(owner);
        uint256 marketId = market.createMarket(
            "Test Market",
            TEST_PROTOCOL,
            450, // 4.5% target
            1 hours,
            true // auto settlement enabled
        );

        // Place bets
        vm.prank(user1);
        market.placeBet(marketId, 10 ether, true); // YES

        vm.prank(user2);
        market.placeBet(marketId, 15 ether, false); // NO

        // Fast forward past market end
        vm.warp(block.timestamp + 2 hours);

        // Update yield data again to avoid stale data
        vm.prank(dataProvider);
        yieldOracle.updateYieldRate(TEST_PROTOCOL, 500); // 5%

        // Attempt auto settlement
        market.attemptAutoSettlement(marketId);

        // Check market was settled
        PredictYieldMarket.Market memory marketData = market.getMarket(
            marketId
        );
        assertEq(marketData.actualYieldRate, 500);
        assertEq(
            uint256(marketData.status),
            uint256(PredictYieldMarket.MarketStatus.Settled)
        );
    }

    function testAutoSettlementFailures() public {
        // Create market without auto settlement
        vm.prank(owner);
        uint256 marketId = market.createMarket(
            "Test Market",
            TEST_PROTOCOL,
            450,
            1 hours,
            false
        );

        vm.warp(block.timestamp + 2 hours);

        vm.expectRevert("Auto settlement not enabled");
        market.attemptAutoSettlement(marketId);
    }

    function testCanAutoSettle() public {
        // Set up yield data with high confidence
        vm.prank(dataProvider);
        yieldOracle.updateYieldRate(TEST_PROTOCOL, 500);

        // Create market with auto settlement
        vm.prank(owner);
        uint256 marketId = market.createMarket(
            "Test Market",
            TEST_PROTOCOL,
            450,
            1 hours,
            true
        );

        // Before market ends
        (bool canSettle, string memory reason) = market.canAutoSettle(marketId);
        assertFalse(canSettle);
        assertEq(reason, "Market has not ended");

        // After market ends - but update yield data first to avoid staleness
        vm.warp(block.timestamp + 2 hours);
        vm.prank(dataProvider);
        yieldOracle.updateYieldRate(TEST_PROTOCOL, 500); // Update after time warp

        (canSettle, reason) = market.canAutoSettle(marketId);
        assertTrue(canSettle);
        assertEq(reason, "Ready for auto settlement");
    }

    /*//////////////////////////////////////////////////////////////
                          REWARDS CLAIMING TESTS
    //////////////////////////////////////////////////////////////*/

    function testClaimRewards() public {
        // Create market
        vm.prank(owner);
        uint256 marketId = market.createMarket(
            "Test Market",
            TEST_PROTOCOL,
            450,
            1 hours,
            false
        );

        // Place bets
        uint256 yesAmount = 10 ether;
        uint256 noAmount = 20 ether;

        vm.prank(user1);
        uint256 betId1 = market.placeBet(marketId, yesAmount, true); // YES

        vm.prank(user2);
        market.placeBet(marketId, noAmount, false); // NO

        // Fast forward and settle market (YES wins)
        vm.warp(block.timestamp + 2 hours);

        vm.prank(owner);
        market.settleMarket(marketId, 500); // 5% > 4.5%, so YES wins

        // Calculate expected rewards
        uint256 platformFeeAmount = (noAmount * 100) / 10000; // 1% fee
        uint256 rewardPool = noAmount - platformFeeAmount;
        uint256 expectedReward = yesAmount + rewardPool;

        uint256 balanceBefore = fxrp.balanceOf(user1);
        uint256 feeRecipientBalanceBefore = fxrp.balanceOf(feeRecipient);

        // Claim rewards
        vm.prank(user1);
        market.claimRewards(betId1);

        // Check balances
        assertEq(fxrp.balanceOf(user1), balanceBefore + expectedReward);
        assertEq(
            fxrp.balanceOf(feeRecipient),
            feeRecipientBalanceBefore + platformFeeAmount
        );

        // Check bet is marked as claimed
        PredictYieldMarket.Bet memory bet = market.getBet(betId1);
        assertTrue(bet.claimed);
    }

    /*//////////////////////////////////////////////////////////////
                           FTSO INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetCurrentYieldFromOracle() public {
        // Set up yield data
        vm.prank(dataProvider);
        yieldOracle.updateYieldRate(TEST_PROTOCOL, 450);

        (uint256 rate, uint256 confidence, uint256 age) = market
            .getCurrentYieldFromOracle(TEST_PROTOCOL);

        assertEq(rate, 450);
        assertGt(confidence, 0);
        assertEq(age, 0); // Just updated
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testUpdateYieldOracle() public {
        // Deploy new oracle
        FTSOv2YieldOracle newOracle = new FTSOv2YieldOracle(
            address(contractRegistry),
            owner
        );

        vm.prank(owner);
        market.updateYieldOracle(address(newOracle));

        assertEq(address(market.yieldOracle()), address(newOracle));
    }

    function testUpdateMinConfidenceScore() public {
        vm.prank(owner);
        market.updateMinConfidenceScore(8000); // 80%

        assertEq(market.minConfidenceScore(), 8000);
    }

    function testUpdateSettings() public {
        vm.prank(owner);
        market.updateSettings(
            2 ether, // New min stake
            500 ether, // New max stake
            200, // New platform fee (2%)
            address(0x5) // New fee recipient
        );

        assertEq(market.minStakeAmount(), 2 ether);
        assertEq(market.maxStakeAmount(), 500 ether);
        assertEq(market.platformFee(), 200);
        assertEq(market.feeRecipient(), address(0x5));
    }

    /*//////////////////////////////////////////////////////////////
                           INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testFullMarketFlowWithAutoSettlement() public {
        // 1. Set up yield data
        vm.prank(dataProvider);
        yieldOracle.updateYieldRate(TEST_PROTOCOL, 470); // 4.7%

        // 2. Create market with auto settlement
        vm.prank(owner);
        uint256 marketId = market.createMarket(
            "Will Aave USDC yield exceed 4.5%?",
            TEST_PROTOCOL,
            450, // 4.5% target
            7 days,
            true // auto settlement
        );

        // 3. Multiple users place bets
        vm.prank(user1);
        uint256 betId1 = market.placeBet(marketId, 50 ether, true); // YES

        vm.prank(user2);
        uint256 betId2 = market.placeBet(marketId, 30 ether, false); // NO

        // 4. Fast forward to after market end
        vm.warp(block.timestamp + 8 days);

        // 5. Update yield data to avoid staleness
        vm.prank(dataProvider);
        yieldOracle.updateYieldRate(TEST_PROTOCOL, 470); // 4.7%

        // 6. Auto settle the market
        market.attemptAutoSettlement(marketId);

        // 7. Verify settlement
        PredictYieldMarket.Market memory marketData = market.getMarket(
            marketId
        );
        assertEq(marketData.actualYieldRate, 470);
        assertEq(
            uint256(marketData.status),
            uint256(PredictYieldMarket.MarketStatus.Settled)
        );

        // 8. Winner claims rewards
        vm.prank(user1);
        market.claimRewards(betId1); // Winning bet (YES, 4.7% > 4.5%)

        // 9. Verify final state
        assertTrue(market.getBet(betId1).claimed);
        assertFalse(market.getBet(betId2).claimed); // Losing bet can't claim

        // Check that losing bet cannot claim
        vm.prank(user2);
        vm.expectRevert("Bet did not win");
        market.claimRewards(betId2);
    }
}
