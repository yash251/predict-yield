// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IFTSOv2.sol";

/**
 * @title FTSOv2YieldOracle
 * @notice Oracle contract that integrates FTSOv2 block-latency feeds with DeFi yield data
 * @dev Provides real-time yield predictions using Flare's FTSOv2 infrastructure
 */
contract FTSOv2YieldOracle is Ownable, ReentrancyGuard, IYieldDataAggregator {
    using FeedIds for bytes21;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum age for feed data in seconds (5 minutes)
    uint256 public constant MAX_FEED_AGE = 300;

    /// @notice Maximum historical data points to store
    uint256 public constant MAX_HISTORICAL_POINTS = 1000;

    /// @notice Basis points for percentage calculations (100% = 10000)
    uint256 public constant BASIS_POINTS = 10000;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice FTSOv2 interface for real-time data feeds
    IFTSOv2Interface public ftsoV2;

    /// @notice Contract registry for getting FTSOv2 address
    IContractRegistry public contractRegistry;

    /// @notice Mapping of protocol name to current yield data
    mapping(string => YieldData) public currentYieldRates;

    /// @notice Mapping of protocol to historical yield data
    mapping(string => YieldData[]) public historicalYieldRates;

    /// @notice Mapping of protocol to authorized data providers
    mapping(string => mapping(address => bool)) public authorizedProviders;

    /// @notice Mapping of feed ID to protocol name for price correlation
    mapping(bytes21 => string) public feedToProtocol;

    /// @notice Protocol names list for iteration
    string[] public protocols;

    /// @notice Mapping to check if protocol exists
    mapping(string => bool) public protocolExists;

    /// @notice Block timestamp when feeds were last updated
    mapping(string => uint64) public lastUpdateTime;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event YieldRateUpdated(
        string indexed protocol,
        uint256 rate,
        uint256 confidence,
        address indexed provider,
        uint64 timestamp
    );

    event ProtocolAdded(string indexed protocol, bytes21 feedId);
    event ProviderAuthorized(string indexed protocol, address indexed provider);
    event ProviderRevoked(string indexed protocol, address indexed provider);
    event FeedCorrelationUpdated(
        string indexed protocol,
        uint256 priceChange,
        uint256 yieldChange
    );

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAuthorizedProvider(string calldata protocol) {
        require(
            authorizedProviders[protocol][msg.sender] || msg.sender == owner(),
            "Not authorized provider"
        );
        _;
    }

    modifier validProtocol(string calldata protocol) {
        require(protocolExists[protocol], "Protocol does not exist");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _contractRegistry,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_contractRegistry != address(0), "Invalid contract registry");

        contractRegistry = IContractRegistry(_contractRegistry);
        ftsoV2 = contractRegistry.getFtsoV2();

        // Initialize common DeFi protocols
        _initializeProtocols();
    }

    /*//////////////////////////////////////////////////////////////
                           FTSO DATA INTEGRATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get real-time price data from FTSOv2 for yield correlation
     * @param feedId The feed ID to query
     * @return value Current price value
     * @return decimals Number of decimals
     * @return timestamp Data timestamp
     */
    function getFTSOPrice(
        bytes21 feedId
    ) external view returns (uint256 value, int8 decimals, uint64 timestamp) {
        return ftsoV2.getFeedById(feedId);
    }

    /**
     * @notice Get multiple FTSO prices for correlation analysis
     * @param feedIds Array of feed IDs
     * @return values Array of price values
     * @return decimals Array of decimal places
     * @return timestamp Common timestamp
     */
    function getFTSOPrices(
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
        return ftsoV2.getFeedsById(feedIds);
    }

    /*//////////////////////////////////////////////////////////////
                          YIELD DATA MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get current yield rate for a protocol
     * @param protocol Protocol identifier
     * @return yieldData Current yield data
     */
    function getCurrentYieldRate(
        string calldata protocol
    )
        external
        view
        override
        validProtocol(protocol)
        returns (YieldData memory yieldData)
    {
        yieldData = currentYieldRates[protocol];

        // Check if data is fresh
        if (block.timestamp - yieldData.timestamp > MAX_FEED_AGE) {
            yieldData.confidence = yieldData.confidence / 2; // Reduce confidence for stale data
        }
    }

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
        override
        validProtocol(protocol)
        returns (uint256[] memory rates, uint64[] memory timestamps)
    {
        YieldData[] storage history = historicalYieldRates[protocol];

        // Count valid entries in range
        uint256 count = 0;
        for (uint256 i = 0; i < history.length; i++) {
            if (history[i].timestamp >= from && history[i].timestamp <= to) {
                count++;
            }
        }

        rates = new uint256[](count);
        timestamps = new uint64[](count);

        // Fill arrays
        uint256 index = 0;
        for (uint256 i = 0; i < history.length && index < count; i++) {
            if (history[i].timestamp >= from && history[i].timestamp <= to) {
                rates[index] = history[i].rate;
                timestamps[index] = history[i].timestamp;
                index++;
            }
        }
    }

    /**
     * @notice Update yield rate with enhanced validation and correlation analysis
     * @param protocol Protocol identifier
     * @param rate New yield rate in basis points
     */
    function updateYieldRate(
        string calldata protocol,
        uint256 rate
    )
        external
        override
        onlyAuthorizedProvider(protocol)
        validProtocol(protocol)
    {
        require(rate <= 50000, "Yield rate too high"); // Max 500%

        YieldData storage current = currentYieldRates[protocol];

        // Calculate confidence based on price correlation and time since last update
        uint256 confidence = _calculateConfidence(protocol, rate);

        // Update current yield data
        current.rate = rate;
        current.timestamp = uint64(block.timestamp);
        current.confidence = confidence;
        current.source = msg.sender;

        // Store historical data
        _storeHistoricalData(protocol, current);

        // Update last update time
        lastUpdateTime[protocol] = uint64(block.timestamp);

        emit YieldRateUpdated(
            protocol,
            rate,
            confidence,
            msg.sender,
            uint64(block.timestamp)
        );
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a new protocol with associated feed ID
     * @param protocol Protocol name
     * @param feedId Associated FTSO feed ID for correlation
     */
    function addProtocol(
        string calldata protocol,
        bytes21 feedId
    ) external onlyOwner {
        require(!protocolExists[protocol], "Protocol already exists");
        require(bytes(protocol).length > 0, "Invalid protocol name");

        protocolExists[protocol] = true;
        protocols.push(protocol);
        feedToProtocol[feedId] = protocol;

        // Initialize with default yield data
        currentYieldRates[protocol] = YieldData({
            rate: 0,
            timestamp: uint64(block.timestamp),
            confidence: 0,
            source: address(0)
        });

        emit ProtocolAdded(protocol, feedId);
    }

    /**
     * @notice Authorize a data provider for a protocol
     * @param protocol Protocol name
     * @param provider Provider address
     */
    function authorizeProvider(
        string calldata protocol,
        address provider
    ) external onlyOwner validProtocol(protocol) {
        require(provider != address(0), "Invalid provider address");
        authorizedProviders[protocol][provider] = true;
        emit ProviderAuthorized(protocol, provider);
    }

    /**
     * @notice Revoke authorization for a data provider
     * @param protocol Protocol name
     * @param provider Provider address
     */
    function revokeProvider(
        string calldata protocol,
        address provider
    ) external onlyOwner validProtocol(protocol) {
        authorizedProviders[protocol][provider] = false;
        emit ProviderRevoked(protocol, provider);
    }

    /**
     * @notice Update FTSOv2 contract address
     */
    function updateFTSOv2() external onlyOwner {
        ftsoV2 = contractRegistry.getFtsoV2();
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize common DeFi protocols
     */
    function _initializeProtocols() internal {
        // Add common DeFi protocols with their associated feed IDs
        _addInitialProtocol("AAVE_USDC", FeedIds.USDC_USD);
        _addInitialProtocol("AAVE_USDT", FeedIds.USDT_USD);
        _addInitialProtocol("AAVE_ETH", FeedIds.ETH_USD);
        _addInitialProtocol("COMPOUND_USDC", FeedIds.USDC_USD);
        _addInitialProtocol("COMPOUND_ETH", FeedIds.ETH_USD);
    }

    /**
     * @notice Add initial protocol during construction
     * @param protocol Protocol name
     * @param feedId Associated feed ID
     */
    function _addInitialProtocol(
        string memory protocol,
        bytes21 feedId
    ) internal {
        protocolExists[protocol] = true;
        protocols.push(protocol);
        feedToProtocol[feedId] = protocol;

        currentYieldRates[protocol] = YieldData({
            rate: 0,
            timestamp: uint64(block.timestamp),
            confidence: 0,
            source: address(0)
        });
    }

    /**
     * @notice Calculate confidence score based on various factors
     * @param protocol Protocol identifier
     * @param newRate New yield rate
     * @return confidence Confidence score (0-10000 basis points)
     */
    function _calculateConfidence(
        string calldata protocol,
        uint256 newRate
    ) internal view returns (uint256 confidence) {
        YieldData storage current = currentYieldRates[protocol];

        // Base confidence starts at 8000 (80%)
        confidence = 8000;

        // Reduce confidence for large rate changes
        if (current.rate > 0) {
            uint256 change = newRate > current.rate
                ? newRate - current.rate
                : current.rate - newRate;
            uint256 changePercent = (change * BASIS_POINTS) / current.rate;

            if (changePercent > 2000) {
                // >20% change
                confidence = confidence / 2;
            } else if (changePercent > 1000) {
                // >10% change
                confidence = (confidence * 80) / 100;
            }
        }

        // Reduce confidence for stale data from same provider
        uint256 timeSinceUpdate = block.timestamp - current.timestamp;
        if (timeSinceUpdate > 3600) {
            // > 1 hour
            confidence = (confidence * 90) / 100;
        }

        // Increase confidence for frequent updates
        if (timeSinceUpdate < 300) {
            // < 5 minutes
            confidence = (confidence * 110) / 100;
            if (confidence > BASIS_POINTS) confidence = BASIS_POINTS;
        }
    }

    /**
     * @notice Store historical yield data with rotation
     * @param protocol Protocol identifier
     * @param data Yield data to store
     */
    function _storeHistoricalData(
        string calldata protocol,
        YieldData memory data
    ) internal {
        YieldData[] storage history = historicalYieldRates[protocol];

        // Add new data point
        history.push(data);

        // Rotate old data if we exceed max points
        if (history.length > MAX_HISTORICAL_POINTS) {
            // Remove oldest 10% of data points
            uint256 removeCount = MAX_HISTORICAL_POINTS / 10;
            for (uint256 i = 0; i < history.length - removeCount; i++) {
                history[i] = history[i + removeCount];
            }
            for (uint256 i = 0; i < removeCount; i++) {
                history.pop();
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get all supported protocols
     * @return Array of protocol names
     */
    function getSupportedProtocols() external view returns (string[] memory) {
        return protocols;
    }

    /**
     * @notice Check if a provider is authorized for a protocol
     * @param protocol Protocol name
     * @param provider Provider address
     * @return Whether the provider is authorized
     */
    function isAuthorizedProvider(
        string calldata protocol,
        address provider
    ) external view returns (bool) {
        return authorizedProviders[protocol][provider];
    }

    /**
     * @notice Get protocol associated with a feed ID
     * @param feedId Feed ID
     * @return protocol Protocol name
     */
    function getProtocolForFeed(
        bytes21 feedId
    ) external view returns (string memory protocol) {
        return feedToProtocol[feedId];
    }

    /**
     * @notice Get yield rate with enhanced metadata
     * @param protocol Protocol identifier
     * @return rate Current yield rate
     * @return confidence Confidence score
     * @return age Age of data in seconds
     * @return provider Data provider address
     */
    function getYieldRateWithMetadata(
        string calldata protocol
    )
        external
        view
        validProtocol(protocol)
        returns (
            uint256 rate,
            uint256 confidence,
            uint256 age,
            address provider
        )
    {
        YieldData storage data = currentYieldRates[protocol];
        rate = data.rate;
        confidence = data.confidence;
        age = block.timestamp - data.timestamp;
        provider = data.source;

        // Adjust confidence for age
        if (age > MAX_FEED_AGE) {
            confidence = confidence / 2;
        }
    }

    /**
     * @notice Calculate average yield rate over a time period
     * @param protocol Protocol identifier
     * @param duration Duration in seconds to look back
     * @return avgRate Average yield rate
     * @return dataPoints Number of data points used
     */
    function getAverageYieldRate(
        string calldata protocol,
        uint256 duration
    )
        external
        view
        validProtocol(protocol)
        returns (uint256 avgRate, uint256 dataPoints)
    {
        uint64 cutoffTime = uint64(block.timestamp - duration);
        YieldData[] storage history = historicalYieldRates[protocol];

        uint256 sum = 0;
        dataPoints = 0;

        for (uint256 i = 0; i < history.length; i++) {
            if (history[i].timestamp >= cutoffTime) {
                sum += history[i].rate;
                dataPoints++;
            }
        }

        avgRate = dataPoints > 0 ? sum / dataPoints : 0;
    }
}
