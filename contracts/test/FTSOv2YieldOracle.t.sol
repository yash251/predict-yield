// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FTSOv2YieldOracle.sol";
import "../src/interfaces/IFTSOv2.sol";

/**
 * @title MockFTSOv2
 * @notice Mock FTSOv2 contract for testing
 */
contract MockFTSOv2 is IFTSOv2Interface {
    mapping(bytes21 => uint256) public feedValues;
    mapping(bytes21 => int8) public feedDecimals;
    uint64 public currentTimestamp;

    constructor() {
        currentTimestamp = uint64(block.timestamp);

        // Initialize some test feeds
        feedValues[FeedIds.USDC_USD] = 100000; // $1.00000 with 5 decimals
        feedValues[FeedIds.ETH_USD] = 245000000; // $2450.00000 with 5 decimals
        feedValues[FeedIds.BTC_USD] = 6900000000; // $69000.00000 with 5 decimals

        feedDecimals[FeedIds.USDC_USD] = 5;
        feedDecimals[FeedIds.ETH_USD] = 5;
        feedDecimals[FeedIds.BTC_USD] = 5;
    }

    function setFeedValue(
        bytes21 feedId,
        uint256 value,
        int8 decimals
    ) external {
        feedValues[feedId] = value;
        feedDecimals[feedId] = decimals;
        currentTimestamp = uint64(block.timestamp);
    }

    function getFeedById(
        bytes21 feedId
    )
        external
        view
        returns (uint256 value, int8 decimals, uint64 feedTimestamp)
    {
        return (feedValues[feedId], feedDecimals[feedId], currentTimestamp);
    }

    function getFeedByIdInWei(
        bytes21 feedId
    ) external view returns (uint256 value, uint64 feedTimestamp) {
        uint256 feedValue = feedValues[feedId];
        int8 feedDecimal = feedDecimals[feedId];

        // Convert to 18 decimals (Wei)
        if (feedDecimal <= 18) {
            value = feedValue * (10 ** (18 - uint8(feedDecimal)));
        } else {
            value = feedValue / (10 ** (uint8(feedDecimal) - 18));
        }

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
            uint64 feedTimestamp
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
    ) external view returns (uint256[] memory values, uint64 feedTimestamp) {
        values = new uint256[](feedIds.length);

        for (uint256 i = 0; i < feedIds.length; i++) {
            uint256 feedValue = feedValues[feedIds[i]];
            int8 feedDecimal = feedDecimals[feedIds[i]];

            // Convert to 18 decimals (Wei)
            if (feedDecimal <= 18) {
                values[i] = feedValue * (10 ** (18 - uint8(feedDecimal)));
            } else {
                values[i] = feedValue / (10 ** (uint8(feedDecimal) - 18));
            }
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
 * @title FTSOv2YieldOracleTest
 * @notice Test suite for FTSOv2YieldOracle contract
 */
contract FTSOv2YieldOracleTest is Test {
    FTSOv2YieldOracle public oracle;
    MockFTSOv2 public mockFTSOv2;
    MockContractRegistry public contractRegistry;

    address public owner = address(0x1);
    address public provider1 = address(0x2);
    address public provider2 = address(0x3);
    address public user = address(0x4);

    string constant AAVE_USDC = "AAVE_USDC";
    string constant COMPOUND_ETH = "COMPOUND_ETH";

    event YieldRateUpdated(
        string indexed protocol,
        uint256 rate,
        uint256 confidence,
        address indexed provider,
        uint64 timestamp
    );

    event ProtocolAdded(string indexed protocol, bytes21 feedId);

    function setUp() public {
        // Deploy mocks
        mockFTSOv2 = new MockFTSOv2();
        contractRegistry = new MockContractRegistry(address(mockFTSOv2));

        // Deploy oracle
        vm.prank(owner);
        oracle = new FTSOv2YieldOracle(address(contractRegistry), owner);

        // Authorize providers
        vm.startPrank(owner);
        oracle.authorizeProvider(AAVE_USDC, provider1);
        oracle.authorizeProvider(COMPOUND_ETH, provider1);
        oracle.authorizeProvider(AAVE_USDC, provider2);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testDeployment() public {
        assertEq(address(oracle.contractRegistry()), address(contractRegistry));
        assertEq(address(oracle.ftsoV2()), address(mockFTSOv2));
        assertEq(oracle.owner(), owner);
        assertEq(oracle.MAX_FEED_AGE(), 300);
        assertEq(oracle.MAX_HISTORICAL_POINTS(), 1000);
        assertEq(oracle.BASIS_POINTS(), 10000);
    }

    function testInitialProtocols() public {
        string[] memory protocols = oracle.getSupportedProtocols();
        assertGt(protocols.length, 0);

        // Check that initial protocols are properly set up
        assertTrue(oracle.protocolExists(AAVE_USDC));
        assertTrue(oracle.protocolExists("AAVE_USDT"));
        assertTrue(oracle.protocolExists("AAVE_ETH"));
        assertTrue(oracle.protocolExists("COMPOUND_USDC"));
        assertTrue(oracle.protocolExists(COMPOUND_ETH));
    }

    /*//////////////////////////////////////////////////////////////
                        FTSO INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetFTSOPrice() public {
        (uint256 value, int8 decimals, uint64 timestamp) = oracle.getFTSOPrice(
            FeedIds.USDC_USD
        );

        assertEq(value, 100000); // $1.00000
        assertEq(decimals, 5);
        assertEq(timestamp, mockFTSOv2.currentTimestamp());
    }

    function testGetFTSOPrices() public {
        bytes21[] memory feedIds = new bytes21[](2);
        feedIds[0] = FeedIds.USDC_USD;
        feedIds[1] = FeedIds.ETH_USD;

        (
            uint256[] memory values,
            int8[] memory decimals,
            uint64 timestamp
        ) = oracle.getFTSOPrices(feedIds);

        assertEq(values.length, 2);
        assertEq(decimals.length, 2);
        assertEq(values[0], 100000); // USDC
        assertEq(values[1], 245000000); // ETH
        assertEq(decimals[0], 5);
        assertEq(decimals[1], 5);
        assertEq(timestamp, mockFTSOv2.currentTimestamp());
    }

    /*//////////////////////////////////////////////////////////////
                        YIELD DATA MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testUpdateYieldRate() public {
        uint256 rate = 450; // 4.5%

        vm.expectEmit(true, false, false, true);
        emit YieldRateUpdated(
            AAVE_USDC,
            rate,
            8800,
            provider1,
            uint64(block.timestamp)
        );

        vm.prank(provider1);
        oracle.updateYieldRate(AAVE_USDC, rate);

        IYieldDataAggregator.YieldData memory data = oracle.getCurrentYieldRate(
            AAVE_USDC
        );
        assertEq(data.rate, rate);
        assertEq(data.source, provider1);
        assertEq(data.timestamp, block.timestamp);
        assertGt(data.confidence, 0);
    }

    function testUpdateYieldRateUnauthorized() public {
        vm.prank(user);
        vm.expectRevert("Not authorized provider");
        oracle.updateYieldRate(AAVE_USDC, 450);
    }

    function testUpdateYieldRateInvalidProtocol() public {
        vm.prank(provider1);
        vm.expectRevert("Not authorized provider"); // Authorization is checked first
        oracle.updateYieldRate("INVALID_PROTOCOL", 450);
    }

    function testUpdateYieldRateTooHigh() public {
        vm.prank(provider1);
        vm.expectRevert("Yield rate too high");
        oracle.updateYieldRate(AAVE_USDC, 50001); // > 500%
    }

    function testGetCurrentYieldRate() public {
        uint256 rate = 650; // 6.5%

        vm.prank(provider1);
        oracle.updateYieldRate(AAVE_USDC, rate);

        IYieldDataAggregator.YieldData memory data = oracle.getCurrentYieldRate(
            AAVE_USDC
        );
        assertEq(data.rate, rate);
        assertEq(data.source, provider1);
        assertGt(data.confidence, 0);
    }

    function testGetCurrentYieldRateStaleData() public {
        uint256 rate = 450;

        vm.prank(provider1);
        oracle.updateYieldRate(AAVE_USDC, rate);

        // Fast forward past MAX_FEED_AGE
        vm.warp(block.timestamp + oracle.MAX_FEED_AGE() + 1);

        IYieldDataAggregator.YieldData memory data = oracle.getCurrentYieldRate(
            AAVE_USDC
        );
        assertEq(data.rate, rate);
        // Confidence should be reduced for stale data
        assertLt(data.confidence, 8000);
    }

    function testHistoricalYieldRates() public {
        uint256[] memory rates = new uint256[](3);
        rates[0] = 400; // 4.0%
        rates[1] = 450; // 4.5%
        rates[2] = 500; // 5.0%

        uint64 startTime = uint64(block.timestamp);

        // Add historical data points
        for (uint256 i = 0; i < rates.length; i++) {
            vm.warp(startTime + i * 3600); // 1 hour apart
            vm.prank(provider1);
            oracle.updateYieldRate(AAVE_USDC, rates[i]);
        }

        // Query historical data
        (uint256[] memory returnedRates, uint64[] memory timestamps) = oracle
            .getHistoricalYieldRates(
                AAVE_USDC,
                startTime,
                uint64(block.timestamp)
            );

        assertEq(returnedRates.length, 3);
        assertEq(timestamps.length, 3);

        for (uint256 i = 0; i < rates.length; i++) {
            assertEq(returnedRates[i], rates[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testAddProtocol() public {
        string memory newProtocol = "UNISWAP_V3";
        bytes21 feedId = FeedIds.ETH_USD;

        vm.expectEmit(true, false, false, true);
        emit ProtocolAdded(newProtocol, feedId);

        vm.prank(owner);
        oracle.addProtocol(newProtocol, feedId);

        assertTrue(oracle.protocolExists(newProtocol));
        assertEq(oracle.getProtocolForFeed(feedId), newProtocol);

        // Should be able to get current yield rate (will be default values)
        IYieldDataAggregator.YieldData memory data = oracle.getCurrentYieldRate(
            newProtocol
        );
        assertEq(data.rate, 0);
        assertEq(data.confidence, 0);
    }

    function testAddProtocolAlreadyExists() public {
        vm.prank(owner);
        vm.expectRevert("Protocol already exists");
        oracle.addProtocol(AAVE_USDC, FeedIds.USDC_USD);
    }

    function testAddProtocolEmptyName() public {
        vm.prank(owner);
        vm.expectRevert("Invalid protocol name");
        oracle.addProtocol("", FeedIds.USDC_USD);
    }

    function testAuthorizeProvider() public {
        address newProvider = address(0x5);

        vm.prank(owner);
        oracle.authorizeProvider(AAVE_USDC, newProvider);

        assertTrue(oracle.isAuthorizedProvider(AAVE_USDC, newProvider));
    }

    function testAuthorizeProviderInvalidAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid provider address");
        oracle.authorizeProvider(AAVE_USDC, address(0));
    }

    function testRevokeProvider() public {
        assertTrue(oracle.isAuthorizedProvider(AAVE_USDC, provider1));

        vm.prank(owner);
        oracle.revokeProvider(AAVE_USDC, provider1);

        assertFalse(oracle.isAuthorizedProvider(AAVE_USDC, provider1));
    }

    function testUpdateFTSOv2() public {
        MockFTSOv2 newFTSOv2 = new MockFTSOv2();
        MockContractRegistry newRegistry = new MockContractRegistry(
            address(newFTSOv2)
        );

        // First update the contract registry
        vm.prank(owner);
        oracle = new FTSOv2YieldOracle(address(newRegistry), owner);

        vm.prank(owner);
        oracle.updateFTSOv2();

        assertEq(address(oracle.ftsoV2()), address(newFTSOv2));
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetYieldRateWithMetadata() public {
        uint256 rate = 550; // 5.5%

        vm.prank(provider1);
        oracle.updateYieldRate(AAVE_USDC, rate);

        (
            uint256 returnedRate,
            uint256 confidence,
            uint256 age,
            address provider
        ) = oracle.getYieldRateWithMetadata(AAVE_USDC);

        assertEq(returnedRate, rate);
        assertGt(confidence, 0);
        assertEq(age, 0); // Just updated
        assertEq(provider, provider1);
    }

    function testGetYieldRateWithMetadataStale() public {
        uint256 rate = 550;

        vm.prank(provider1);
        oracle.updateYieldRate(AAVE_USDC, rate);

        // Fast forward past MAX_FEED_AGE
        vm.warp(block.timestamp + oracle.MAX_FEED_AGE() + 100);

        (
            uint256 returnedRate,
            uint256 confidence,
            uint256 age,
            address provider
        ) = oracle.getYieldRateWithMetadata(AAVE_USDC);

        assertEq(returnedRate, rate);
        assertLt(confidence, 8000); // Reduced confidence
        assertEq(age, oracle.MAX_FEED_AGE() + 100);
        assertEq(provider, provider1);
    }

    function testGetAverageYieldRate() public {
        uint256[] memory rates = new uint256[](4);
        rates[0] = 400; // 4.0%
        rates[1] = 450; // 4.5%
        rates[2] = 500; // 5.0%
        rates[3] = 550; // 5.5%

        uint64 startTime = uint64(block.timestamp);

        // Add data points 1 hour apart
        for (uint256 i = 0; i < rates.length; i++) {
            vm.warp(startTime + i * 3600);
            vm.prank(provider1);
            oracle.updateYieldRate(AAVE_USDC, rates[i]);
        }

        // Get average over last 2 hours (should include last 3 data points)
        (uint256 avgRate, uint256 dataPoints) = oracle.getAverageYieldRate(
            AAVE_USDC,
            2 * 3600
        );

        assertEq(dataPoints, 3); // Last 3 points
        assertEq(avgRate, (rates[1] + rates[2] + rates[3]) / 3); // Average of 450, 500, and 550 = 500
    }

    function testGetSupportedProtocols() public {
        string[] memory protocols = oracle.getSupportedProtocols();
        assertGt(protocols.length, 0);

        // Add a new protocol and verify it appears in the list
        string memory newProtocol = "TEST_PROTOCOL";
        vm.prank(owner);
        oracle.addProtocol(newProtocol, FeedIds.BTC_USD);

        string[] memory updatedProtocols = oracle.getSupportedProtocols();
        assertEq(updatedProtocols.length, protocols.length + 1);
    }

    /*//////////////////////////////////////////////////////////////
                           CONFIDENCE TESTS
    //////////////////////////////////////////////////////////////*/

    function testConfidenceCalculation() public {
        uint256 initialRate = 500; // 5.0%

        // Set initial rate
        vm.prank(provider1);
        oracle.updateYieldRate(AAVE_USDC, initialRate);

        IYieldDataAggregator.YieldData memory data1 = oracle
            .getCurrentYieldRate(AAVE_USDC);
        uint256 initialConfidence = data1.confidence;

        // Update with small change (should maintain high confidence)
        vm.warp(block.timestamp + 100);
        vm.prank(provider1);
        oracle.updateYieldRate(AAVE_USDC, 505); // 0.5% increase

        IYieldDataAggregator.YieldData memory data2 = oracle
            .getCurrentYieldRate(AAVE_USDC);
        assertGe(data2.confidence, (initialConfidence * 80) / 100); // Should not drop below 80% of initial

        // Update with large change (should reduce confidence)
        vm.warp(block.timestamp + 100);
        vm.prank(provider1);
        oracle.updateYieldRate(AAVE_USDC, 750); // 50% increase

        IYieldDataAggregator.YieldData memory data3 = oracle
            .getCurrentYieldRate(AAVE_USDC);
        assertLt(data3.confidence, data2.confidence); // Should be lower
    }

    function testFrequentUpdatesBoostConfidence() public {
        // Update very frequently (should boost confidence)
        vm.prank(provider1);
        oracle.updateYieldRate(AAVE_USDC, 500);

        IYieldDataAggregator.YieldData memory data1 = oracle
            .getCurrentYieldRate(AAVE_USDC);

        // Update again quickly
        vm.warp(block.timestamp + 60); // 1 minute later
        vm.prank(provider1);
        oracle.updateYieldRate(AAVE_USDC, 505);

        IYieldDataAggregator.YieldData memory data2 = oracle
            .getCurrentYieldRate(AAVE_USDC);
        assertGe(data2.confidence, data1.confidence); // Should maintain or boost confidence
    }

    /*//////////////////////////////////////////////////////////////
                           INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testFullYieldDataFlow() public {
        // 1. Add new protocol
        string memory protocol = "CURVE_3POOL";
        vm.prank(owner);
        oracle.addProtocol(protocol, FeedIds.USDC_USD);

        // 2. Authorize provider
        vm.prank(owner);
        oracle.authorizeProvider(protocol, provider1);

        // 3. Provider updates yield rate multiple times
        uint256[] memory rates = new uint256[](5);
        rates[0] = 300;
        rates[1] = 320;
        rates[2] = 350;
        rates[3] = 340;
        rates[4] = 360;

        for (uint256 i = 0; i < rates.length; i++) {
            vm.warp(block.timestamp + i * 1800); // 30 minutes apart
            vm.prank(provider1);
            oracle.updateYieldRate(protocol, rates[i]);
        }

        // 4. Verify current state
        IYieldDataAggregator.YieldData memory current = oracle
            .getCurrentYieldRate(protocol);
        assertEq(current.rate, rates[4]); // Latest rate
        assertEq(current.source, provider1);

        // 5. Verify historical data (expect all 5 data points)
        (uint256[] memory historicalRates, ) = oracle.getHistoricalYieldRates(
            protocol,
            uint64(block.timestamp - 2 * 3600), // Last 2 hours
            uint64(block.timestamp)
        );
        assertEq(historicalRates.length, 5); // All 5 data points should be within 2 hours

        // 6. Verify average calculation
        (uint256 avgRate, uint256 dataPoints) = oracle.getAverageYieldRate(
            protocol,
            3600
        ); // Last hour
        assertGt(dataPoints, 0);
        assertGt(avgRate, 0);

        // 7. Verify FTSO price correlation works
        (uint256 price, , ) = oracle.getFTSOPrice(FeedIds.USDC_USD);
        assertEq(price, 100000); // USDC should be $1.00000
    }
}
