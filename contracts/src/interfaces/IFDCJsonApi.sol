// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFDCHub
 * @notice Interface for Flare Data Connector Hub contract
 * @dev Used to submit attestation requests for external data validation
 */
interface IFDCHub {
    /**
     * @notice Submit an attestation request
     * @param attestationType Type of attestation (e.g., "JsonApi")
     * @param sourceId Source identifier for the data
     * @param messageIntegrityCode Expected response hash (MIC)
     * @param requestBody Encoded request parameters
     * @return Request ID for tracking
     */
    function requestAttestation(
        bytes32 attestationType,
        bytes32 sourceId,
        bytes32 messageIntegrityCode,
        bytes calldata requestBody
    ) external payable returns (bytes32);

    /**
     * @notice Get attestation fee for a specific type
     * @param attestationType Type of attestation
     * @return fee Required fee in wei
     */
    function getAttestationFee(
        bytes32 attestationType
    ) external view returns (uint256 fee);
}

/**
 * @title IFDCRelay
 * @notice Interface for FDC Relay contract that stores Merkle roots
 * @dev Used to verify attestation proofs against consensus data
 */
interface IFDCRelay {
    /**
     * @notice Get the Merkle root for a specific voting round
     * @param votingRound The voting round number
     * @return merkleRoot The Merkle root hash
     * @return isFinalized Whether the voting round is finalized
     */
    function getMerkleRoot(
        uint256 votingRound
    ) external view returns (bytes32 merkleRoot, bool isFinalized);

    /**
     * @notice Get the current voting round
     * @return currentRound Current voting round number
     */
    function getCurrentVotingRound()
        external
        view
        returns (uint256 currentRound);

    /**
     * @notice Check if a voting round has enough signature weight (50%+)
     * @param votingRound The voting round to check
     * @return hasConsensus Whether consensus was reached
     * @return signatureWeight Total signature weight percentage
     */
    function getConsensusStatus(
        uint256 votingRound
    ) external view returns (bool hasConsensus, uint256 signatureWeight);
}

/**
 * @title IFDCVerification
 * @notice Interface for FDC verification contract
 * @dev Used to verify Merkle proofs against stored roots
 */
interface IFDCVerification {
    /**
     * @notice Verify an attestation response using Merkle proof
     * @param votingRound The voting round when data was attested
     * @param merkleProof Array of proof hashes
     * @param responseHash Hash of the attestation response
     * @return isValid Whether the proof is valid
     */
    function verifyAttestationProof(
        uint256 votingRound,
        bytes32[] calldata merkleProof,
        bytes32 responseHash
    ) external view returns (bool isValid);

    /**
     * @notice Verify and parse JsonApi attestation response
     * @param votingRound The voting round when data was attested
     * @param merkleProof Array of proof hashes
     * @param response The complete attestation response
     * @return isValid Whether the proof is valid
     * @return parsedData The parsed response data
     */
    function verifyJsonApiResponse(
        uint256 votingRound,
        bytes32[] calldata merkleProof,
        bytes calldata response
    ) external view returns (bool isValid, bytes memory parsedData);
}

/**
 * @title JsonApiAttestationTypes
 * @notice Library defining JsonApi attestation request and response structures
 */
library JsonApiAttestationTypes {
    /**
     * @notice JsonApi attestation request structure
     */
    struct JsonApiRequest {
        bytes32 attestationType; // "JsonApi"
        bytes32 sourceId; // API source identifier
        string url; // Target URL for data retrieval
        string apiKey; // API key (optional, can be empty)
        string requestBody; // Request payload (for POST requests)
        string requestMethod; // HTTP method (GET, POST, etc.)
        string responseJqFilter; // JQ filter for processing response
        uint64 lowerBoundaryTimestamp; // Earliest acceptable data timestamp
        uint64 upperBoundaryTimestamp; // Latest acceptable data timestamp
    }

    /**
     * @notice JsonApi attestation response structure
     */
    struct JsonApiResponse {
        bytes32 attestationType; // "JsonApi"
        bytes32 sourceId; // API source identifier
        uint64 votingRound; // Voting round when attested
        uint64 lowestUsedTimestamp; // Actual data timestamp used
        bytes32 requestId; // Original request identifier
        bytes responseData; // ABI-encoded response data
        bool isValid; // Whether the response is valid
    }

    /**
     * @notice Yield data structure for DeFi protocols
     */
    struct YieldDataResponse {
        string protocol; // Protocol identifier (e.g., "AAVE_USDC")
        uint256 yieldRate; // Yield rate in basis points
        uint64 timestamp; // Data timestamp
        uint256 tvl; // Total Value Locked
        uint256 confidence; // Confidence score (0-10000)
        string source; // Data source URL
    }
}

/**
 * @title IFDCYieldAttestation
 * @notice Interface for yield data attestation using FDC JsonApi
 * @dev Specialized interface for DeFi yield rate validation
 */
interface IFDCYieldAttestation {
    /**
     * @notice Request yield data attestation for a DeFi protocol
     * @param protocol Protocol identifier (e.g., "AAVE_USDC")
     * @param apiUrl Target API URL for yield data
     * @param jqFilter JQ filter for extracting yield data
     * @return requestId Attestation request ID
     */
    function requestYieldAttestation(
        string calldata protocol,
        string calldata apiUrl,
        string calldata jqFilter
    ) external payable returns (bytes32 requestId);

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
        returns (
            bool isValid,
            JsonApiAttestationTypes.YieldDataResponse memory yieldData
        );

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
    ) external;

    /**
     * @notice Get the minimum required signature weight for acceptance
     * @return minWeight Minimum signature weight (basis points)
     */
    function getMinSignatureWeight() external view returns (uint256 minWeight);

    /**
     * @notice Check if a protocol is supported for yield attestation
     * @param protocol Protocol identifier
     * @return isSupported Whether the protocol is supported
     */
    function isSupportedProtocol(
        string calldata protocol
    ) external view returns (bool isSupported);
}

/**
 * @title FDC Constants
 * @notice Library containing FDC-related constants
 */
library FDCConstants {
    /// @notice JsonApi attestation type identifier
    bytes32 public constant JSON_API_TYPE = keccak256("JsonApi");

    /// @notice Minimum signature weight required (50% + 1)
    uint256 public constant MIN_SIGNATURE_WEIGHT = 5001; // 50.01%

    /// @notice Maximum voting round age for acceptance (24 hours worth of rounds)
    uint256 public constant MAX_VOTING_ROUND_AGE = 8640; // ~24 hours at 10s rounds

    /// @notice Maximum response data size (32KB)
    uint256 public constant MAX_RESPONSE_SIZE = 32768;

    /// @notice Standard JsonApi source IDs
    bytes32 public constant AAVE_SOURCE_ID = keccak256("AAVE_API");
    bytes32 public constant COMPOUND_SOURCE_ID = keccak256("COMPOUND_API");
    bytes32 public constant CURVE_SOURCE_ID = keccak256("CURVE_API");
}

/**
 * @title MerkleProofLib
 * @notice Library for Merkle proof verification utilities
 */
library MerkleProofLib {
    /**
     * @notice Verify a Merkle proof
     * @param proof Array of proof hashes
     * @param root Merkle root
     * @param leaf Leaf hash to verify
     * @return valid Whether the proof is valid
     */
    function verify(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool valid) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash <= proofElement) {
                // Hash(current computed hash + current element of the proof)
                computedHash = keccak256(
                    abi.encodePacked(computedHash, proofElement)
                );
            } else {
                // Hash(current element of the proof + current computed hash)
                computedHash = keccak256(
                    abi.encodePacked(proofElement, computedHash)
                );
            }
        }

        // Check if the computed hash (root) is equal to the provided root
        return computedHash == root;
    }

    /**
     * @notice Create leaf hash for attestation response
     * @param response Attestation response data
     * @return hash Keccak256 hash of the response
     */
    function hashAttestationResponse(
        bytes memory response
    ) internal pure returns (bytes32 hash) {
        return keccak256(response);
    }
}
