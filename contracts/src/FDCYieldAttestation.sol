// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IFDCJsonApi.sol";
import "./interfaces/IFTSOv2.sol";

/**
 * @title FDCYieldAttestation
 * @notice Contract for attesting DeFi yield data using Flare Data Connector JsonApi
 * @dev Integrates with FDC for external yield data validation and Merkle proof verification
 */
contract FDCYieldAttestation is
    Ownable,
    ReentrancyGuard,
    IFDCYieldAttestation,
    IYieldDataAggregator
{
    using MerkleProofLib for bytes32[];
    using JsonApiAttestationTypes for JsonApiAttestationTypes.JsonApiRequest;
    using JsonApiAttestationTypes for JsonApiAttestationTypes.JsonApiResponse;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum age for attestation data (24 hours in seconds)
    uint256 public constant MAX_ATTESTATION_AGE = 86400;

    /// @notice Minimum signature weight for accepting attestations (50.01%)
    uint256 public constant MIN_SIGNATURE_WEIGHT = 5001;

    /// @notice Maximum yield rate (500% in basis points)
    uint256 public constant MAX_YIELD_RATE = 50000;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice FDC Hub contract for submitting attestation requests
    IFDCHub public fdcHub;

    /// @notice FDC Relay contract for Merkle root verification
    IFDCRelay public fdcRelay;

    /// @notice FDC Verification contract for proof validation
    IFDCVerification public fdcVerification;

    /// @notice FTSOv2 Yield Oracle for fallback and correlation
    IYieldDataAggregator public ftsoYieldOracle;

    /// @notice Mapping of protocol to API configuration
    mapping(string => ApiConfig) public protocolApiConfigs;

    /// @notice Mapping of protocol to current yield data from FDC
    mapping(string => YieldData) public fdcYieldData;

    /// @notice Mapping of protocol to historical FDC yield data
    mapping(string => YieldData[]) public fdcHistoricalData;

    /// @notice Mapping of request ID to protocol
    mapping(bytes32 => string) public requestToProtocol;

    /// @notice Mapping of protocol to pending request IDs
    mapping(string => bytes32[]) public protocolPendingRequests;

    /// @notice Supported protocols list
    string[] public supportedProtocols;

    /// @notice Mapping to check if protocol is supported
    mapping(string => bool) public protocolSupported;

    /// @notice Consensus threshold for using FDC data (basis points)
    uint256 public consensusThreshold = 7000; // 70%

    /// @notice FDC attestation fee per request
    uint256 public attestationFee;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct ApiConfig {
        string apiUrl; // API endpoint URL
        string jqFilter; // JQ filter for extracting yield data
        uint256 updateInterval; // Update interval in seconds
        uint64 lastUpdate; // Last update timestamp
        bool isActive; // Whether the API is active
        bytes32 sourceId; // FDC source identifier
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event YieldAttestationRequested(
        string indexed protocol,
        bytes32 indexed requestId,
        string apiUrl,
        uint256 fee
    );

    event YieldAttestationReceived(
        string indexed protocol,
        bytes32 indexed requestId,
        uint256 votingRound,
        uint256 yieldRate,
        uint256 signatureWeight
    );

    event FDCYieldDataUpdated(
        string indexed protocol,
        uint256 rate,
        uint64 timestamp,
        uint256 confidence,
        bytes32 requestId
    );

    event ProtocolApiConfigured(
        string indexed protocol,
        string apiUrl,
        string jqFilter,
        bytes32 sourceId
    );

    event ConsensusDataUsed(
        string indexed protocol,
        uint256 fdcRate,
        uint256 ftsoRate,
        uint256 finalRate,
        string source
    );

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlySupportedProtocol(string calldata protocol) {
        require(protocolSupported[protocol], "Protocol not supported");
        _;
    }

    modifier validYieldRate(uint256 rate) {
        require(rate <= MAX_YIELD_RATE, "Yield rate exceeds maximum");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _fdcHub,
        address _fdcRelay,
        address _fdcVerification,
        address _ftsoYieldOracle,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_fdcHub != address(0), "Invalid FDC Hub address");
        require(_fdcRelay != address(0), "Invalid FDC Relay address");
        require(
            _fdcVerification != address(0),
            "Invalid FDC Verification address"
        );
        require(_ftsoYieldOracle != address(0), "Invalid FTSO Oracle address");

        fdcHub = IFDCHub(_fdcHub);
        fdcRelay = IFDCRelay(_fdcRelay);
        fdcVerification = IFDCVerification(_fdcVerification);
        ftsoYieldOracle = IYieldDataAggregator(_ftsoYieldOracle);

        // Get attestation fee
        attestationFee = fdcHub.getAttestationFee(FDCConstants.JSON_API_TYPE);

        // Initialize default protocols
        _initializeProtocols();
    }

    /*//////////////////////////////////////////////////////////////
                       FDC YIELD ATTESTATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Request yield data attestation for a DeFi protocol
     * @param protocol Protocol identifier
     * @param apiUrl Target API URL (optional override)
     * @param jqFilter JQ filter (optional override)
     * @return requestId Attestation request ID
     */
    function requestYieldAttestation(
        string calldata protocol,
        string calldata apiUrl,
        string calldata jqFilter
    )
        external
        payable
        override
        onlySupportedProtocol(protocol)
        nonReentrant
        returns (bytes32 requestId)
    {
        require(msg.value >= attestationFee, "Insufficient fee");

        ApiConfig storage config = protocolApiConfigs[protocol];
        require(config.isActive, "Protocol API not active");

        // Use provided URL/filter or default from config
        string memory targetUrl;
        string memory filter;

        if (bytes(apiUrl).length > 0) {
            targetUrl = apiUrl;
        } else {
            targetUrl = config.apiUrl;
        }

        if (bytes(jqFilter).length > 0) {
            filter = jqFilter;
        } else {
            filter = config.jqFilter;
        }

        // Create JsonApi request
        JsonApiAttestationTypes.JsonApiRequest
            memory request = JsonApiAttestationTypes.JsonApiRequest({
                attestationType: FDCConstants.JSON_API_TYPE,
                sourceId: config.sourceId,
                url: targetUrl,
                apiKey: "", // API key handled offchain by data providers
                requestBody: "",
                requestMethod: "GET",
                responseJqFilter: filter,
                lowerBoundaryTimestamp: uint64(block.timestamp - 3600), // 1 hour ago
                upperBoundaryTimestamp: uint64(block.timestamp + 300) // 5 minutes ahead
            });

        // Encode request
        bytes memory encodedRequest = abi.encode(request);

        // Calculate Message Integrity Code (MIC) - expected response hash
        bytes32 mic = keccak256(abi.encodePacked(protocol, block.timestamp));

        // Submit attestation request
        requestId = fdcHub.requestAttestation{value: msg.value}(
            FDCConstants.JSON_API_TYPE,
            config.sourceId,
            mic,
            encodedRequest
        );

        // Track request
        requestToProtocol[requestId] = protocol;
        protocolPendingRequests[protocol].push(requestId);

        // Update last request time
        config.lastUpdate = uint64(block.timestamp);

        emit YieldAttestationRequested(
            protocol,
            requestId,
            targetUrl,
            msg.value
        );
    }

    /**
     * @notice Verify and process yield attestation response
     * @param votingRound Voting round when data was attested
     * @param merkleProof Merkle proof for validation
     * @param response Complete attestation response
     * @return isValid Whether the proof is valid
     * @return yieldData Parsed yield data
     */
    function verifyYieldAttestation(
        uint256 votingRound,
        bytes32[] calldata merkleProof,
        bytes calldata response
    )
        external
        view
        override
        returns (
            bool isValid,
            JsonApiAttestationTypes.YieldDataResponse memory yieldData
        )
    {
        // Check if voting round is finalized and has consensus
        (bytes32 merkleRoot, bool isFinalized) = fdcRelay.getMerkleRoot(
            votingRound
        );
        require(isFinalized, "Voting round not finalized");

        (bool hasConsensus, uint256 signatureWeight) = fdcRelay
            .getConsensusStatus(votingRound);
        require(hasConsensus, "Insufficient consensus");
        require(
            signatureWeight >= MIN_SIGNATURE_WEIGHT,
            "Insufficient signature weight"
        );

        // Verify merkle proof
        bytes32 responseHash = MerkleProofLib.hashAttestationResponse(response);
        isValid = MerkleProofLib.verify(merkleProof, merkleRoot, responseHash);

        if (isValid) {
            // Parse response data
            JsonApiAttestationTypes.JsonApiResponse memory apiResponse = abi
                .decode(response, (JsonApiAttestationTypes.JsonApiResponse));

            // Decode yield data from response
            yieldData = abi.decode(
                apiResponse.responseData,
                (JsonApiAttestationTypes.YieldDataResponse)
            );

            // Validate yield data
            require(
                yieldData.yieldRate <= MAX_YIELD_RATE,
                "Yield rate too high"
            );
            require(
                block.timestamp - yieldData.timestamp <= MAX_ATTESTATION_AGE,
                "Data too stale"
            );
        }
    }

    /**
     * @notice Submit verified yield data to oracle
     * @param protocol Protocol identifier
     * @param votingRound Voting round for verification
     * @param merkleProof Merkle proof
     * @param response Attestation response
     */
    function submitVerifiedYieldData(
        string calldata protocol,
        uint256 votingRound,
        bytes32[] calldata merkleProof,
        bytes calldata response
    ) external override onlySupportedProtocol(protocol) nonReentrant {
        // Verify the attestation
        (
            bool isValid,
            JsonApiAttestationTypes.YieldDataResponse memory yieldData
        ) = this.verifyYieldAttestation(votingRound, merkleProof, response);

        require(isValid, "Invalid attestation proof");
        require(
            keccak256(bytes(yieldData.protocol)) == keccak256(bytes(protocol)),
            "Protocol mismatch"
        );

        // Get signature weight for confidence calculation
        (, uint256 signatureWeight) = fdcRelay.getConsensusStatus(votingRound);

        // Calculate confidence based on signature weight and data freshness
        uint256 confidence = _calculateFDCConfidence(
            signatureWeight,
            yieldData.timestamp
        );

        // Update FDC yield data
        fdcYieldData[protocol] = YieldData({
            rate: yieldData.yieldRate,
            timestamp: yieldData.timestamp,
            confidence: confidence,
            source: msg.sender
        });

        // Store historical data
        fdcHistoricalData[protocol].push(fdcYieldData[protocol]);

        // Clean up old historical data
        _cleanupHistoricalData(protocol);

        // Extract request ID from the first pending request (simplified)
        bytes32 requestId = bytes32(0);
        if (protocolPendingRequests[protocol].length > 0) {
            requestId = protocolPendingRequests[protocol][0];
            // Remove processed request
            _removePendingRequest(protocol, requestId);
        }

        emit YieldAttestationReceived(
            protocol,
            requestId,
            votingRound,
            yieldData.yieldRate,
            signatureWeight
        );

        emit FDCYieldDataUpdated(
            protocol,
            yieldData.yieldRate,
            yieldData.timestamp,
            confidence,
            requestId
        );
    }

    /*//////////////////////////////////////////////////////////////
                        YIELD DATA AGGREGATOR FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get current yield rate using consensus between FDC and FTSO data
     * @param protocol Protocol identifier
     * @return yieldData Consensus yield data
     */
    function getCurrentYieldRate(
        string calldata protocol
    )
        external
        view
        override
        onlySupportedProtocol(protocol)
        returns (YieldData memory yieldData)
    {
        YieldData memory fdcData = fdcYieldData[protocol];
        YieldData memory ftsoData = ftsoYieldOracle.getCurrentYieldRate(
            protocol
        );

        // Use FDC data if confidence is high enough and data is fresh
        if (
            fdcData.confidence >= consensusThreshold &&
            block.timestamp - fdcData.timestamp <= MAX_ATTESTATION_AGE
        ) {
            return fdcData;
        }

        // Use FTSO data if FDC data is not reliable
        if (
            ftsoData.confidence >= consensusThreshold &&
            block.timestamp - ftsoData.timestamp <= 3600 // 1 hour
        ) {
            return ftsoData;
        }

        // Create consensus data by averaging if both sources are available but low confidence
        if (fdcData.rate > 0 && ftsoData.rate > 0) {
            uint256 weightedRate = (fdcData.rate *
                fdcData.confidence +
                ftsoData.rate *
                ftsoData.confidence) /
                (fdcData.confidence + ftsoData.confidence);

            return
                YieldData({
                    rate: weightedRate,
                    timestamp: uint64(block.timestamp),
                    confidence: (fdcData.confidence + ftsoData.confidence) / 2,
                    source: address(this)
                });
        }

        // Fallback to the more recent data
        return fdcData.timestamp > ftsoData.timestamp ? fdcData : ftsoData;
    }

    /**
     * @notice Get historical yield rates from FDC attestations
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
        onlySupportedProtocol(protocol)
        returns (uint256[] memory rates, uint64[] memory timestamps)
    {
        YieldData[] storage history = fdcHistoricalData[protocol];

        // Count entries in range
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
     * @notice Update yield rate (called by authorized sources)
     * @dev This maintains compatibility with IYieldDataAggregator
     * @param protocol Protocol identifier
     * @param rate New yield rate in basis points
     */
    function updateYieldRate(
        string calldata protocol,
        uint256 rate
    ) external override onlySupportedProtocol(protocol) validYieldRate(rate) {
        // For this implementation, direct updates are only allowed by owner
        require(msg.sender == owner(), "Only owner can directly update rates");

        fdcYieldData[protocol] = YieldData({
            rate: rate,
            timestamp: uint64(block.timestamp),
            confidence: 9500, // High confidence for manual updates
            source: msg.sender
        });

        emit FDCYieldDataUpdated(
            protocol,
            rate,
            uint64(block.timestamp),
            9500,
            bytes32(0)
        );
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configure API settings for a protocol
     * @param protocol Protocol identifier
     * @param apiUrl API endpoint URL
     * @param jqFilter JQ filter for extracting data
     * @param updateInterval Update interval in seconds
     * @param sourceId FDC source identifier
     */
    function configureProtocolApi(
        string calldata protocol,
        string calldata apiUrl,
        string calldata jqFilter,
        uint256 updateInterval,
        bytes32 sourceId
    ) external onlyOwner {
        require(bytes(protocol).length > 0, "Invalid protocol");
        require(bytes(apiUrl).length > 0, "Invalid API URL");
        require(updateInterval >= 300, "Update interval too short"); // Min 5 minutes

        protocolApiConfigs[protocol] = ApiConfig({
            apiUrl: apiUrl,
            jqFilter: jqFilter,
            updateInterval: updateInterval,
            lastUpdate: 0,
            isActive: true,
            sourceId: sourceId
        });

        if (!protocolSupported[protocol]) {
            protocolSupported[protocol] = true;
            supportedProtocols.push(protocol);
        }

        emit ProtocolApiConfigured(protocol, apiUrl, jqFilter, sourceId);
    }

    /**
     * @notice Update consensus threshold
     * @param newThreshold New threshold in basis points
     */
    function updateConsensusThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold <= 10000, "Invalid threshold");
        require(newThreshold >= 5000, "Threshold too low"); // Min 50%
        consensusThreshold = newThreshold;
    }

    /**
     * @notice Update FDC contract addresses
     */
    function updateFDCContracts(
        address _fdcHub,
        address _fdcRelay,
        address _fdcVerification
    ) external onlyOwner {
        require(_fdcHub != address(0), "Invalid FDC Hub");
        require(_fdcRelay != address(0), "Invalid FDC Relay");
        require(_fdcVerification != address(0), "Invalid FDC Verification");

        fdcHub = IFDCHub(_fdcHub);
        fdcRelay = IFDCRelay(_fdcRelay);
        fdcVerification = IFDCVerification(_fdcVerification);

        // Update attestation fee
        attestationFee = fdcHub.getAttestationFee(FDCConstants.JSON_API_TYPE);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get minimum required signature weight
     * @return minWeight Minimum signature weight (basis points)
     */
    function getMinSignatureWeight()
        external
        pure
        override
        returns (uint256 minWeight)
    {
        return MIN_SIGNATURE_WEIGHT;
    }

    /**
     * @notice Check if protocol is supported
     * @param protocol Protocol identifier
     * @return isSupported Whether protocol is supported
     */
    function isSupportedProtocol(
        string calldata protocol
    ) external view override returns (bool isSupported) {
        return protocolSupported[protocol];
    }

    /**
     * @notice Get API configuration for a protocol
     * @param protocol Protocol identifier
     * @return config API configuration
     */
    function getProtocolApiConfig(
        string calldata protocol
    ) external view returns (ApiConfig memory config) {
        return protocolApiConfigs[protocol];
    }

    /**
     * @notice Get current attestation fee
     * @return fee Current fee in wei
     */
    function getAttestationFee() external view returns (uint256 fee) {
        return attestationFee;
    }

    /**
     * @notice Get pending requests for a protocol
     * @param protocol Protocol identifier
     * @return requests Array of pending request IDs
     */
    function getPendingRequests(
        string calldata protocol
    ) external view returns (bytes32[] memory requests) {
        return protocolPendingRequests[protocol];
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize default protocol configurations
     */
    function _initializeProtocols() internal {
        // Initialize common DeFi protocols with placeholder APIs
        string[5] memory protocols = [
            "AAVE_USDC",
            "AAVE_USDT",
            "AAVE_ETH",
            "COMPOUND_USDC",
            "COMPOUND_ETH"
        ];
        bytes32[5] memory sourceIds = [
            FDCConstants.AAVE_SOURCE_ID,
            FDCConstants.AAVE_SOURCE_ID,
            FDCConstants.AAVE_SOURCE_ID,
            FDCConstants.COMPOUND_SOURCE_ID,
            FDCConstants.COMPOUND_SOURCE_ID
        ];

        for (uint256 i = 0; i < protocols.length; i++) {
            protocolSupported[protocols[i]] = true;
            supportedProtocols.push(protocols[i]);

            protocolApiConfigs[protocols[i]] = ApiConfig({
                apiUrl: "https://api.aave.com/v1/yield", // Placeholder
                jqFilter: ".data.yieldRate",
                updateInterval: 3600, // 1 hour
                lastUpdate: 0,
                isActive: false, // Needs configuration
                sourceId: sourceIds[i]
            });
        }
    }

    /**
     * @notice Calculate confidence score for FDC data
     * @param signatureWeight Signature weight from consensus
     * @param dataTimestamp Timestamp of the data
     * @return confidence Confidence score (0-10000)
     */
    function _calculateFDCConfidence(
        uint256 signatureWeight,
        uint64 dataTimestamp
    ) internal view returns (uint256 confidence) {
        // Base confidence from signature weight
        confidence = (signatureWeight * 10000) / 10000; // Convert percentage to basis points

        // Reduce confidence based on data age
        uint256 age = block.timestamp - dataTimestamp;
        if (age > 3600) {
            // > 1 hour
            confidence = (confidence * 90) / 100;
        }
        if (age > 7200) {
            // > 2 hours
            confidence = (confidence * 80) / 100;
        }
        if (age > MAX_ATTESTATION_AGE) {
            // > 24 hours
            confidence = confidence / 4; // Heavily penalize very old data
        }
    }

    /**
     * @notice Remove processed request from pending list
     * @param protocol Protocol identifier
     * @param requestId Request ID to remove
     */
    function _removePendingRequest(
        string memory protocol,
        bytes32 requestId
    ) internal {
        bytes32[] storage pending = protocolPendingRequests[protocol];
        for (uint256 i = 0; i < pending.length; i++) {
            if (pending[i] == requestId) {
                pending[i] = pending[pending.length - 1];
                pending.pop();
                break;
            }
        }
    }

    /**
     * @notice Clean up old historical data
     * @param protocol Protocol identifier
     */
    function _cleanupHistoricalData(string memory protocol) internal {
        YieldData[] storage history = fdcHistoricalData[protocol];

        // Keep only last 100 entries to manage gas costs
        if (history.length > 100) {
            uint256 removeCount = history.length - 100;
            for (uint256 i = 0; i < 100; i++) {
                history[i] = history[i + removeCount];
            }
            for (uint256 i = 0; i < removeCount; i++) {
                history.pop();
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                           EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emergency withdrawal of contract balance
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");

        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");
    }

    /**
     * @notice Receive function to accept ETH for attestation fees
     */
    receive() external payable {
        // Accept ETH deposits for attestation fees
    }
}
