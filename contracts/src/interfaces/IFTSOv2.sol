// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFTSOv2Interface
 * @notice Interface for FTSOv2 block-latency feeds
 * @dev Based on official Flare FTSOv2 contracts for real-time data feeds
 */
interface IFTSOv2Interface {
    /**
     * @notice Get a single feed value by its ID
     * @param feedId The feed ID as bytes21
     * @return value The feed value
     * @return decimals The number of decimals
     * @return timestamp The timestamp of the feed
     */
    function getFeedById(
        bytes21 feedId
    ) external view returns (uint256 value, int8 decimals, uint64 timestamp);

    /**
     * @notice Get a single feed value by its ID in Wei (18 decimals)
     * @param feedId The feed ID as bytes21
     * @return value The feed value in Wei
     * @return timestamp The timestamp of the feed
     */
    function getFeedByIdInWei(
        bytes21 feedId
    ) external view returns (uint256 value, uint64 timestamp);

    /**
     * @notice Get multiple feed values by their IDs
     * @param feedIds Array of feed IDs as bytes21
     * @return values Array of feed values
     * @return decimals Array of decimal places for each feed
     * @return timestamp Common timestamp for all feeds
     */
    function getFeedsById(
        bytes21[] calldata feedIds
    )
        external
        view
        returns (
            uint256[] memory values,
            int8[] memory decimals,
            uint64 timestamp
        );

    /**
     * @notice Get multiple feed values by their IDs in Wei (18 decimals)
     * @param feedIds Array of feed IDs as bytes21
     * @return values Array of feed values in Wei
     * @return timestamp Common timestamp for all feeds
     */
    function getFeedsByIdInWei(
        bytes21[] calldata feedIds
    ) external view returns (uint256[] memory values, uint64 timestamp);
}

/**
 * @title IContractRegistry
 * @notice Interface for Flare Contract Registry
 * @dev Used to get contract addresses on Flare network
 */
interface IContractRegistry {
    /**
     * @notice Get the FTSOv2 contract instance
     * @return The FTSOv2 interface
     */
    function getFtsoV2() external view returns (IFTSOv2Interface);

    /**
     * @notice Get the Test FTSOv2 contract instance (for testing)
     * @return The Test FTSOv2 interface
     */
    function getTestFtsoV2() external view returns (IFTSOv2Interface);
}

/**
 * @title IFtsoFeedIdConverter
 * @notice Interface for converting feed names to feed IDs
 * @dev Helper contract for generating proper feed IDs
 */
interface IFtsoFeedIdConverter {
    /**
     * @notice Convert category and feed name to feed ID
     * @param category Feed category (1 = crypto, 2 = forex, etc.)
     * @param feedName Feed name (e.g., "FLR/USD")
     * @return feedId The generated feed ID as bytes21
     */
    function getFeedId(
        uint8 category,
        string calldata feedName
    ) external pure returns (bytes21 feedId);
}

/**
 * @title YieldDataAggregator
 * @notice Custom interface for aggregating yield data from multiple sources
 * @dev This will be our custom implementation for DeFi yield prediction markets
 */
interface IYieldDataAggregator {
    struct YieldData {
        uint256 rate; // Yield rate in basis points
        uint64 timestamp; // When the data was last updated
        uint256 confidence; // Confidence score (0-10000 basis points)
        address source; // Data source address
    }

    /**
     * @notice Get current yield rate for a specific DeFi protocol
     * @param protocol Protocol identifier (e.g., "AAVE_USDC")
     * @return yieldData Current yield data
     */
    function getCurrentYieldRate(
        string calldata protocol
    ) external view returns (YieldData memory yieldData);

    /**
     * @notice Get historical yield rates for analysis
     * @param protocol Protocol identifier
     * @param from Start timestamp
     * @param to End timestamp
     * @return rates Array of historical rates
     * @return timestamps Array of timestamps
     */
    function getHistoricalYieldRates(
        string calldata protocol,
        uint64 from,
        uint64 to
    )
        external
        view
        returns (uint256[] memory rates, uint64[] memory timestamps);

    /**
     * @notice Update yield rate (called by data providers)
     * @param protocol Protocol identifier
     * @param rate New yield rate in basis points
     */
    function updateYieldRate(string calldata protocol, uint256 rate) external;
}

// Predefined Feed IDs for commonly used cryptocurrencies
library FeedIds {
    // Crypto feeds (category 01)
    bytes21 public constant FLR_USD =
        0x01464c522f55534400000000000000000000000000; // FLR/USD
    bytes21 public constant BTC_USD =
        0x014254432f55534400000000000000000000000000; // BTC/USD
    bytes21 public constant ETH_USD =
        0x014554482f55534400000000000000000000000000; // ETH/USD
    bytes21 public constant XRP_USD =
        0x015852502f55534400000000000000000000000000; // XRP/USD
    bytes21 public constant USDC_USD =
        0x01555344432f555344000000000000000000000000; // USDC/USD
    bytes21 public constant USDT_USD =
        0x01555344542f555344000000000000000000000000; // USDT/USD
    bytes21 public constant AAVE_USD =
        0x01414156452f555344000000000000000000000000; // AAVE/USD
}
