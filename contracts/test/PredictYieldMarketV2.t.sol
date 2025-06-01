// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PredictYieldMarketV2.sol";
import "../src/FlareSecureRandom.sol";
import "../src/FTSOv2YieldOracle.sol";
import "../src/FDCYieldAttestation.sol";

// Simple interface for testing
interface ISimpleOracle {
    function getYieldData(
        string calldata protocol
    )
        external
        view
        returns (uint256 yieldRate, uint256 timestamp, uint8 decimals);
}

/**
 * @title MockSimpleOracle
 * @notice Simple mock oracle for testing
 */
contract MockSimpleOracle is ISimpleOracle {
    mapping(string => uint256) public yieldRates;
    mapping(string => uint256) public timestamps;

    function setYieldData(
        string calldata protocol,
        uint256 rate,
        uint256 timestamp_
    ) external {
        yieldRates[protocol] = rate;
        timestamps[protocol] = timestamp_;
    }

    function getYieldData(
        string calldata protocol
    )
        external
        view
        override
        returns (uint256 yieldRate, uint256 timestamp, uint8 decimals)
    {
        return (yieldRates[protocol], timestamps[protocol], 18);
    }
}

/**
 * @title MockFXRPV2
 * @notice Enhanced mock FXRP token for testing V2 features
 */
contract MockFXRPV2 is IFAsset {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    string public name = "Test Flare XRP";
    string public symbol = "tFXRP";
    uint8 public decimals = 18;

    // Enhanced minting with collateral simulation
    uint256 public collateralRatio = 150; // 150% collateralization
    mapping(address => uint256) public collateralBalances;

    event Minted(address indexed to, uint256 amount, uint256 collateralUsed);
    event Redeemed(
        address indexed from,
        uint256 amount,
        uint256 collateralReturned
    );

    function mint(
        uint256 amount,
        uint256 collateralAmount
    ) external returns (bool) {
        uint256 requiredCollateral = (amount * collateralRatio) / 100;
        require(
            collateralAmount >= requiredCollateral,
            "Insufficient collateral"
        );

        balanceOf[msg.sender] += amount;
        totalSupply += amount;
        collateralBalances[msg.sender] += collateralAmount;

        emit Minted(msg.sender, amount, collateralAmount);
        return true;
    }

    function redeem(uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");

        uint256 collateralToReturn = (collateralBalances[msg.sender] * amount) /
            balanceOf[msg.sender];

        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        collateralBalances[msg.sender] -= collateralToReturn;

        payable(msg.sender).transfer(collateralToReturn);

        emit Redeemed(msg.sender, amount, collateralToReturn);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(
            allowance[from][msg.sender] >= amount,
            "Insufficient allowance"
        );

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;

        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    // Additional required interface methods
    function getCollateralRatio() external view returns (uint256 ratio) {
        return collateralRatio;
    }

    function getMinMintAmount() external view returns (uint256 amount) {
        return 1e18; // 1 FXRP minimum
    }

    function isMintingEnabled() external view returns (bool enabled) {
        return true;
    }

    // Test utilities
    function mintForTesting(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}

/**
 * @title PredictYieldMarketV2Test
 * @notice Comprehensive test suite for enhanced prediction market
 */
contract PredictYieldMarketV2Test is Test {
    PredictYieldMarketV2 public market;
    MockFXRPV2 public fxrp;
    FlareSecureRandom public secureRandom;
    MockSimpleOracle public ftsoOracle;
    MockFlareEntropy public mockEntropy;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public user3 = address(0x4);

    uint256 constant INITIAL_FXRP_BALANCE = 10000e18;
    uint256 constant TARGET_YIELD = 500; // 5% yield target
    uint256 constant BETTING_DURATION = 1 hours;

    event MarketCreated(
        uint256 indexed marketId,
        address indexed creator,
        string description,
        uint256 targetYield,
        uint256 bettingEndTime,
        uint256 settlementTime,
        bool useRandomDuration
    );

    event BetPlaced(
        uint256 indexed marketId,
        address indexed bettor,
        address indexed position,
        uint256 amount,
        uint256 totalStake
    );

    event MarketSettled(
        uint256 indexed marketId,
        uint256 finalYield,
        address winner,
        uint256 totalPayout,
        uint256 platformFees
    );

    function setUp() public {
        // Deploy mock entropy
        mockEntropy = new MockFlareEntropy();

        // Deploy FXRP token
        fxrp = new MockFXRPV2();

        // Deploy SecureRandom
        vm.prank(owner);
        secureRandom = new FlareSecureRandom(address(mockEntropy), owner);

        // Deploy oracles (using minimal mock setups)
        vm.prank(owner);
        ftsoOracle = new MockSimpleOracle();

        // Deploy enhanced market
        vm.prank(owner);
        market = new PredictYieldMarketV2(
            address(fxrp),
            address(ftsoOracle),
            address(secureRandom),
            owner
        );

        // Fund test accounts
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(address(secureRandom), 10 ether);

        // Mint FXRP for testing
        fxrp.mintForTesting(user1, INITIAL_FXRP_BALANCE);
        fxrp.mintForTesting(user2, INITIAL_FXRP_BALANCE);
        fxrp.mintForTesting(user3, INITIAL_FXRP_BALANCE);

        // Setup approvals
        vm.prank(user1);
        fxrp.approve(address(market), type(uint256).max);
        vm.prank(user2);
        fxrp.approve(address(market), type(uint256).max);
        vm.prank(user3);
        fxrp.approve(address(market), type(uint256).max);

        // Setup mock entropy
        mockEntropy.setConsensusEntropy(
            1000,
            keccak256("test-consensus"),
            true
        );
    }

    /*//////////////////////////////////////////////////////////////
                           DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testDeployment() public {
        assertEq(address(market.fxrp()), address(fxrp));
        assertEq(address(market.ftsoOracle()), address(ftsoOracle));
        assertEq(address(market.secureRandom()), address(secureRandom));
        assertEq(market.owner(), owner);

        assertEq(market.nextMarketId(), 1);
        assertEq(market.totalMarkets(), 0);
        assertEq(market.totalVolume(), 0);

        assertEq(market.YES_TOKEN(), address(0x1));
        assertEq(market.NO_TOKEN(), address(0x2));
    }

    function testInitialConfiguration() public {
        (
            uint256 minBettingDuration,
            uint256 maxBettingDuration,
            uint256 settlementDelay,
            uint256 minStakeAmount,
            uint256 maxStakeAmount,
            uint256 platformFeeRate,
            uint256 oracleConfidenceThreshold
        ) = market.config();

        assertEq(minBettingDuration, 30 minutes);
        assertEq(maxBettingDuration, 7 days);
        assertEq(settlementDelay, 1 hours);
        assertEq(minStakeAmount, 1e18);
        assertEq(maxStakeAmount, 1000e18);
        assertEq(platformFeeRate, 200); // 2%
        assertEq(oracleConfidenceThreshold, 70);
    }

    /*//////////////////////////////////////////////////////////////
                         MARKET CREATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testCreateBasicMarket() public {
        vm.expectEmit(true, true, false, true);
        emit MarketCreated(
            1,
            user1,
            "Will USDC yield reach 5% by end of period?",
            TARGET_YIELD,
            block.timestamp + BETTING_DURATION,
            block.timestamp + BETTING_DURATION + 1 hours,
            false
        );

        vm.prank(user1);
        uint256 marketId = market.createMarket(
            "Will USDC yield reach 5% by end of period?",
            TARGET_YIELD,
            BETTING_DURATION,
            false
        );

        assertEq(marketId, 1);
        assertEq(market.totalMarkets(), 1);

        PredictYieldMarketV2.Market memory createdMarket = market.getMarket(
            marketId
        );
        assertEq(createdMarket.id, marketId);
        assertEq(createdMarket.creator, user1);
        assertEq(createdMarket.targetYield, TARGET_YIELD);
        assertEq(
            uint8(createdMarket.status),
            uint8(PredictYieldMarketV2.MarketStatus.Active)
        );
        assertFalse(createdMarket.useRandomDuration);
    }

    function testCreateMarketWithRandomDuration() public {
        vm.prank(user1);
        uint256 marketId = market.createMarket(
            "Will USDC yield reach 5% by end of period?",
            TARGET_YIELD,
            BETTING_DURATION,
            true // Use random duration
        );

        PredictYieldMarketV2.Market memory createdMarket = market.getMarket(
            marketId
        );
        assertTrue(createdMarket.useRandomDuration);
        assertNotEq(createdMarket.randomRequestId, bytes32(0));

        // Duration should be varied (95-115% of original)
        uint256 expectedMin = block.timestamp + (BETTING_DURATION * 95) / 100;
        uint256 expectedMax = block.timestamp + (BETTING_DURATION * 115) / 100;

        assertGe(createdMarket.bettingEndTime, expectedMin);
        assertLe(createdMarket.bettingEndTime, expectedMax);
    }

    function testCreateMarketFailures() public {
        // Empty description
        vm.prank(user1);
        vm.expectRevert("Empty description");
        market.createMarket("", TARGET_YIELD, BETTING_DURATION, false);

        // Invalid target yield
        vm.prank(user1);
        vm.expectRevert("Invalid target yield");
        market.createMarket("Test", 0, BETTING_DURATION, false);

        vm.prank(user1);
        vm.expectRevert("Invalid target yield");
        market.createMarket("Test", 10001, BETTING_DURATION, false); // Over 100%

        // Invalid betting duration
        vm.prank(user1);
        vm.expectRevert("Invalid betting duration");
        market.createMarket("Test", TARGET_YIELD, 10 minutes, false); // Too short

        vm.prank(user1);
        vm.expectRevert("Invalid betting duration");
        market.createMarket("Test", TARGET_YIELD, 8 days, false); // Too long
    }

    /*//////////////////////////////////////////////////////////////
                           BETTING TESTS
    //////////////////////////////////////////////////////////////*/

    function testPlaceBasicBet() public {
        // Create market
        vm.prank(user1);
        uint256 marketId = market.createMarket(
            "Test Market",
            TARGET_YIELD,
            BETTING_DURATION,
            false
        );

        uint256 betAmount = 100e18;
        uint256 balanceBefore = fxrp.balanceOf(user2);

        vm.expectEmit(true, true, true, true);
        emit BetPlaced(
            marketId,
            user2,
            market.YES_TOKEN(),
            betAmount,
            betAmount
        );

        vm.prank(user2);
        market.placeBet(marketId, market.YES_TOKEN(), betAmount);

        // Check balances
        assertEq(fxrp.balanceOf(user2), balanceBefore - betAmount);
        assertEq(fxrp.balanceOf(address(market)), betAmount);

        // Check market state
        PredictYieldMarketV2.Market memory updatedMarket = market.getMarket(
            marketId
        );
        assertEq(updatedMarket.totalYesStake, betAmount);
        assertEq(updatedMarket.totalNoStake, 0);

        // Check user bets
        PredictYieldMarketV2.Bet[] memory userBets = market.getUserBets(
            marketId,
            user2
        );
        assertEq(userBets.length, 1);
        assertEq(userBets[0].bettor, user2);
        assertEq(userBets[0].position, market.YES_TOKEN());
        assertEq(userBets[0].amount, betAmount);
        assertFalse(userBets[0].claimed);

        // Check user markets tracking
        uint256[] memory userMarkets = market.getUserMarkets(user2);
        assertEq(userMarkets.length, 1);
        assertEq(userMarkets[0], marketId);
    }

    function testPlaceMultipleBets() public {
        // Create market
        vm.prank(user1);
        uint256 marketId = market.createMarket(
            "Test Market",
            TARGET_YIELD,
            BETTING_DURATION,
            false
        );

        uint256 yesBetAmount = 200e18;
        uint256 noBetAmount = 150e18;

        // Place YES bet
        vm.prank(user2);
        market.placeBet(marketId, market.YES_TOKEN(), yesBetAmount);

        // Place NO bet
        vm.prank(user3);
        market.placeBet(marketId, market.NO_TOKEN(), noBetAmount);

        PredictYieldMarketV2.Market memory updatedMarket = market.getMarket(
            marketId
        );
        assertEq(updatedMarket.totalYesStake, yesBetAmount);
        assertEq(updatedMarket.totalNoStake, noBetAmount);

        assertEq(market.totalVolume(), yesBetAmount + noBetAmount);
    }

    function testBettingFailures() public {
        // Create market
        vm.prank(user1);
        uint256 marketId = market.createMarket(
            "Test Market",
            TARGET_YIELD,
            BETTING_DURATION,
            false
        );

        // Test invalid position
        vm.prank(user2);
        vm.expectRevert("Invalid position");
        market.placeBet(marketId, address(0x5), 100e18);

        // Test stake below minimum
        vm.prank(user2);
        vm.expectRevert("Stake below minimum");
        market.placeBet(marketId, market.YES_TOKEN(), 0.5e18);

        // Test stake above maximum
        vm.prank(user2);
        vm.expectRevert("Stake above maximum");
        market.placeBet(marketId, market.YES_TOKEN(), 1001e18);

        // Test betting on non-existent market
        vm.prank(user2);
        vm.expectRevert("Invalid market ID");
        market.placeBet(999, market.YES_TOKEN(), 100e18);

        // Test betting after period ends
        vm.prank(user1);
        uint256 marketId2 = market.createMarket(
            "Test Market 2",
            TARGET_YIELD,
            BETTING_DURATION,
            false
        );

        vm.warp(block.timestamp + BETTING_DURATION + 1);

        vm.prank(user2);
        vm.expectRevert("Betting period ended");
        market.placeBet(marketId2, market.YES_TOKEN(), 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                        SETTLEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testMarketSettlement() public {
        // Create and bet on market
        vm.prank(user1);
        uint256 marketId = market.createMarket(
            "Test Market",
            TARGET_YIELD,
            BETTING_DURATION,
            false
        );

        vm.prank(user2);
        market.placeBet(marketId, market.YES_TOKEN(), 200e18);

        vm.prank(user3);
        market.placeBet(marketId, market.NO_TOKEN(), 100e18);

        // Fast forward to settlement time
        vm.warp(block.timestamp + BETTING_DURATION + 1 hours);
        ftsoOracle.setYieldData("USDC", TARGET_YIELD, block.timestamp);

        vm.expectEmit(true, false, false, false);
        emit MarketSettled(marketId, TARGET_YIELD, market.YES_TOKEN(), 0, 0);

        vm.prank(user1);
        market.settleMarket(marketId);

        PredictYieldMarketV2.Market memory settledMarket = market.getMarket(
            marketId
        );
        assertEq(
            uint8(settledMarket.status),
            uint8(PredictYieldMarketV2.MarketStatus.Settled)
        );
        assertEq(settledMarket.finalYield, TARGET_YIELD);
        assertEq(settledMarket.winner, market.YES_TOKEN());
    }

    function testMarketSettlementYieldBelowTarget() public {
        // Create and bet on market
        vm.prank(user1);
        uint256 marketId = market.createMarket(
            "Test Market",
            TARGET_YIELD,
            BETTING_DURATION,
            false
        );

        vm.prank(user2);
        market.placeBet(marketId, market.YES_TOKEN(), 200e18);

        vm.prank(user3);
        market.placeBet(marketId, market.NO_TOKEN(), 100e18);

        // Fast forward to settlement time
        vm.warp(block.timestamp + BETTING_DURATION + 1 hours);
        ftsoOracle.setYieldData("USDC", TARGET_YIELD - 100, block.timestamp);

        vm.prank(user1);
        market.settleMarket(marketId);

        PredictYieldMarketV2.Market memory settledMarket = market.getMarket(
            marketId
        );
        assertEq(settledMarket.finalYield, TARGET_YIELD - 100);
        assertEq(settledMarket.winner, market.NO_TOKEN());
    }

    function testSettlementFailures() public {
        // Create market
        vm.prank(user1);
        uint256 marketId = market.createMarket(
            "Test Market",
            TARGET_YIELD,
            BETTING_DURATION,
            false
        );

        // Test settlement before time
        vm.prank(user1);
        vm.expectRevert("Settlement time not reached");
        market.settleMarket(marketId);

        // Test settlement of non-existent market
        vm.expectRevert("Invalid market ID");
        market.settleMarket(999);
    }

    /*//////////////////////////////////////////////////////////////
                          CLAIMING TESTS
    //////////////////////////////////////////////////////////////*/

    function testClaimWinnings() public {
        // Create and settle market with YES winner
        vm.prank(user1);
        uint256 marketId = market.createMarket(
            "Test Market",
            TARGET_YIELD,
            BETTING_DURATION,
            false
        );

        uint256 yesBet = 200e18;
        uint256 noBet = 100e18;

        vm.prank(user2);
        market.placeBet(marketId, market.YES_TOKEN(), yesBet);

        vm.prank(user3);
        market.placeBet(marketId, market.NO_TOKEN(), noBet);

        // Settle market
        vm.warp(block.timestamp + BETTING_DURATION + 1 hours);
        ftsoOracle.setYieldData("USDC", TARGET_YIELD, block.timestamp);

        vm.prank(user1);
        market.settleMarket(marketId);

        // Calculate expected payout
        uint256 totalStake = yesBet + noBet;
        uint256 platformFees = (totalStake * 200) / 10000; // 2% fee
        uint256 netPool = totalStake - platformFees;
        uint256 expectedPayout = netPool; // Winner takes all (only YES bettor)

        uint256 balanceBefore = fxrp.balanceOf(user2);

        vm.prank(user2);
        market.claimWinnings(marketId);

        uint256 balanceAfter = fxrp.balanceOf(user2);
        assertEq(balanceAfter - balanceBefore, expectedPayout);

        // Check bet marked as claimed
        PredictYieldMarketV2.Bet[] memory userBets = market.getUserBets(
            marketId,
            user2
        );
        assertTrue(userBets[0].claimed);
    }

    function testClaimRefundFromCancelledMarket() public {
        // Create market
        vm.prank(user1);
        uint256 marketId = market.createMarket(
            "Test Market",
            TARGET_YIELD,
            BETTING_DURATION,
            false
        );

        uint256 betAmount = 100e18;
        vm.prank(user2);
        market.placeBet(marketId, market.YES_TOKEN(), betAmount);

        // Mock low confidence oracle data to trigger cancellation
        vm.warp(block.timestamp + BETTING_DURATION + 1 hours);
        ftsoOracle.setYieldData("USDC", 0, block.timestamp - 1000);

        vm.prank(user1);
        market.settleMarket(marketId); // Should cancel due to low confidence

        PredictYieldMarketV2.Market memory cancelledMarket = market.getMarket(
            marketId
        );
        assertEq(
            uint8(cancelledMarket.status),
            uint8(PredictYieldMarketV2.MarketStatus.Cancelled)
        );

        // Claim refund
        uint256 balanceBefore = fxrp.balanceOf(user2);

        vm.prank(user2);
        market.claimWinnings(marketId);

        uint256 balanceAfter = fxrp.balanceOf(user2);
        assertEq(balanceAfter - balanceBefore, betAmount); // Full refund
    }

    function testClaimFailures() public {
        // Create and settle market
        vm.prank(user1);
        uint256 marketId = market.createMarket(
            "Test Market",
            TARGET_YIELD,
            BETTING_DURATION,
            false
        );

        // Test claiming from unsettled market
        vm.prank(user2);
        vm.expectRevert("Market not settled or cancelled");
        market.claimWinnings(marketId);

        // Test claiming with no bets
        vm.prank(user2);
        market.placeBet(marketId, market.YES_TOKEN(), 100e18);

        vm.warp(block.timestamp + BETTING_DURATION + 1 hours);
        ftsoOracle.setYieldData("USDC", TARGET_YIELD, block.timestamp);

        vm.prank(user1);
        market.settleMarket(marketId);

        vm.prank(user3);
        vm.expectRevert("No bets found");
        market.claimWinnings(marketId);
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testCalculatePayout() public {
        // Create market with existing bets
        vm.prank(user1);
        uint256 marketId = market.createMarket(
            "Test Market",
            TARGET_YIELD,
            BETTING_DURATION,
            false
        );

        vm.prank(user2);
        market.placeBet(marketId, market.YES_TOKEN(), 100e18);

        // Calculate payout for additional bet
        uint256 additionalBet = 50e18;
        uint256 payout = market.calculatePayout(
            marketId,
            market.YES_TOKEN(),
            additionalBet
        );

        // Expected calculation:
        // Total stake = 100 + 50 = 150
        // Platform fees = 150 * 2% = 3
        // Net pool = 150 - 3 = 147
        // Position stake = 100 + 50 = 150
        // Payout = (50 * 147) / 150 = 49

        uint256 expectedPayout = (additionalBet * 147e18) / 150e18;
        assertEq(payout, expectedPayout);
    }

    function testGetMarketStats() public {
        assertEq(market.totalMarkets(), 0);
        assertEq(market.totalVolume(), 0);

        // Create markets
        vm.prank(user1);
        market.createMarket("Market 1", TARGET_YIELD, BETTING_DURATION, false);

        vm.prank(user1);
        market.createMarket("Market 2", TARGET_YIELD, BETTING_DURATION, false);

        // Place bets
        vm.prank(user2);
        market.placeBet(1, market.YES_TOKEN(), 100e18);

        vm.prank(user3);
        market.placeBet(2, market.NO_TOKEN(), 200e18);

        (
            uint256 totalMarketsCount,
            uint256 totalVolumeAmount,
            uint256 activeMarkets
        ) = market.getMarketStats();

        assertEq(totalMarketsCount, 2);
        assertEq(totalVolumeAmount, 300e18);
        assertEq(activeMarkets, 2);
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testUpdateConfig() public {
        PredictYieldMarketV2.MarketConfig
            memory newConfig = PredictYieldMarketV2.MarketConfig({
                minBettingDuration: 1 hours,
                maxBettingDuration: 14 days,
                settlementDelay: 2 hours,
                minStakeAmount: 2e18,
                maxStakeAmount: 2000e18,
                platformFeeRate: 300, // 3%
                oracleConfidenceThreshold: 80
            });

        vm.prank(owner);
        market.updateConfig(newConfig);

        (
            uint256 minBettingDuration,
            uint256 maxBettingDuration,
            uint256 settlementDelay,
            uint256 minStakeAmount,
            uint256 maxStakeAmount,
            uint256 platformFeeRate,
            uint256 oracleConfidenceThreshold
        ) = market.config();

        assertEq(minBettingDuration, 1 hours);
        assertEq(maxBettingDuration, 14 days);
        assertEq(settlementDelay, 2 hours);
        assertEq(minStakeAmount, 2e18);
        assertEq(maxStakeAmount, 2000e18);
        assertEq(platformFeeRate, 300);
        assertEq(oracleConfidenceThreshold, 80);
    }

    function testPauseUnpause() public {
        // Pause contract
        vm.prank(owner);
        market.pause();

        // Test that market creation fails when paused
        vm.prank(user1);
        vm.expectRevert("Pausable: paused");
        market.createMarket("Test", TARGET_YIELD, BETTING_DURATION, false);

        // Unpause contract
        vm.prank(owner);
        market.unpause();

        // Test that market creation works again
        vm.prank(user1);
        uint256 marketId = market.createMarket(
            "Test",
            TARGET_YIELD,
            BETTING_DURATION,
            false
        );
        assertEq(marketId, 1);
    }

    function testAdminAccessControl() public {
        PredictYieldMarketV2.MarketConfig memory config = PredictYieldMarketV2
            .MarketConfig({
                minBettingDuration: 1 hours,
                maxBettingDuration: 14 days,
                settlementDelay: 2 hours,
                minStakeAmount: 2e18,
                maxStakeAmount: 2000e18,
                platformFeeRate: 300,
                oracleConfidenceThreshold: 80
            });

        // Test non-owner cannot update config
        vm.prank(user1);
        vm.expectRevert();
        market.updateConfig(config);

        // Test non-owner cannot pause
        vm.prank(user1);
        vm.expectRevert();
        market.pause();

        // Test non-owner cannot emergency withdraw
        vm.prank(user1);
        vm.expectRevert();
        market.emergencyWithdraw(100e18, user1);
    }

    /*//////////////////////////////////////////////////////////////
                         INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testFullMarketLifecycle() public {
        // Step 1: Create market
        vm.prank(user1);
        uint256 marketId = market.createMarket(
            "Will USDC yield reach 5%?",
            TARGET_YIELD,
            BETTING_DURATION,
            false
        );

        // Step 2: Multiple users place bets
        vm.prank(user2);
        market.placeBet(marketId, market.YES_TOKEN(), 300e18);

        vm.prank(user3);
        market.placeBet(marketId, market.NO_TOKEN(), 200e18);

        vm.prank(user1);
        market.placeBet(marketId, market.YES_TOKEN(), 100e18);

        // Step 3: Wait for settlement time
        vm.warp(block.timestamp + BETTING_DURATION + 1 hours);

        // Step 4: Settle market (YES wins)
        ftsoOracle.setYieldData("USDC", TARGET_YIELD + 50, block.timestamp);

        vm.prank(user1);
        market.settleMarket(marketId);

        // Step 5: Winners claim their payouts
        uint256 user2BalanceBefore = fxrp.balanceOf(user2);
        uint256 user1BalanceBefore = fxrp.balanceOf(user1);

        vm.prank(user2);
        market.claimWinnings(marketId);

        vm.prank(user1);
        market.claimWinnings(marketId);

        // Verify payouts received
        assertGt(fxrp.balanceOf(user2), user2BalanceBefore);
        assertGt(fxrp.balanceOf(user1), user1BalanceBefore);

        // Step 6: Loser tries to claim (should get nothing new)
        uint256 user3BalanceBefore = fxrp.balanceOf(user3);
        vm.prank(user3);
        vm.expectRevert("No payout available");
        market.claimWinnings(marketId);
        assertEq(fxrp.balanceOf(user3), user3BalanceBefore);
    }

    function testMultipleMarketsOperations() public {
        // Create multiple markets
        vm.prank(user1);
        uint256 market1 = market.createMarket(
            "Market 1",
            400,
            BETTING_DURATION,
            false
        );

        vm.prank(user2);
        uint256 market2 = market.createMarket(
            "Market 2",
            600,
            BETTING_DURATION,
            false
        );

        // Place bets on different markets
        vm.prank(user1);
        market.placeBet(market1, market.YES_TOKEN(), 100e18);

        vm.prank(user1);
        market.placeBet(market2, market.NO_TOKEN(), 150e18);

        vm.prank(user2);
        market.placeBet(market1, market.NO_TOKEN(), 200e18);

        vm.prank(user3);
        market.placeBet(market2, market.YES_TOKEN(), 250e18);

        // Verify user markets tracking
        uint256[] memory user1Markets = market.getUserMarkets(user1);
        assertEq(user1Markets.length, 2);
        assertTrue(user1Markets[0] == market1 || user1Markets[1] == market1);
        assertTrue(user1Markets[0] == market2 || user1Markets[1] == market2);

        // Verify market states
        PredictYieldMarketV2.Market memory marketData1 = market.getMarket(
            market1
        );
        assertEq(marketData1.totalYesStake, 100e18);
        assertEq(marketData1.totalNoStake, 200e18);

        PredictYieldMarketV2.Market memory marketData2 = market.getMarket(
            market2
        );
        assertEq(marketData2.totalYesStake, 250e18);
        assertEq(marketData2.totalNoStake, 150e18);
    }
}
