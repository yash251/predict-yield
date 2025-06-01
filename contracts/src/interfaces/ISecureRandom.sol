// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IFlareEntropy
 * @notice Interface for accessing Flare blockchain entropy sources
 * @dev Provides access to block-based randomness and consensus entropy
 */
interface IFlareEntropy {
    /**
     * @notice Get the latest block hash entropy
     * @param blockNumber Block number to get hash from
     * @return entropy Block hash as entropy source
     * @return timestamp Block timestamp
     */
    function getBlockEntropy(
        uint256 blockNumber
    ) external view returns (bytes32 entropy, uint256 timestamp);

    /**
     * @notice Get consensus entropy from Flare's scaling protocol
     * @param round Consensus round number
     * @return entropy Consensus-derived entropy
     * @return isFinalized Whether the round is finalized
     */
    function getConsensusEntropy(
        uint256 round
    ) external view returns (bytes32 entropy, bool isFinalized);

    /**
     * @notice Get current consensus round
     * @return round Current active consensus round
     */
    function getCurrentRound() external view returns (uint256 round);
}

/**
 * @title ISecureRandomRequester
 * @notice Interface for contracts that can request randomness
 */
interface ISecureRandomRequester {
    /**
     * @notice Callback function called when randomness is fulfilled
     * @param requestId The request ID that was fulfilled
     * @param randomness The generated random number
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) external;
}

/**
 * @title ISecureRandom
 * @notice Interface for Flare's secure random number generation
 * @dev Implements commit-reveal scheme with block-based entropy for verifiable randomness
 */
interface ISecureRandom {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct RandomRequest {
        address requester; // Contract requesting randomness
        uint256 seed; // User-provided seed
        uint256 commitBlock; // Block when request was committed
        uint256 revealBlock; // Block when randomness can be revealed
        uint256 minDelay; // Minimum blocks to wait before reveal
        uint256 maxDelay; // Maximum blocks to wait before reveal
        bool fulfilled; // Whether request has been fulfilled
        uint256 randomness; // Generated random number (after fulfillment)
        bytes32 entropy; // Block entropy used for generation
    }

    struct CommitRevealConfig {
        uint256 minDelay; // Minimum blocks between commit and reveal
        uint256 maxDelay; // Maximum blocks before request expires
        uint256 commitFee; // Fee required to make a request
        bool useConsensusEntropy; // Whether to use consensus entropy
        uint256 consensusRound; // Specific consensus round to use
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event RandomnessRequested(
        bytes32 indexed requestId,
        address indexed requester,
        uint256 seed,
        uint256 commitBlock,
        uint256 revealBlock
    );

    event RandomnessFulfilled(
        bytes32 indexed requestId,
        address indexed requester,
        uint256 randomness,
        bytes32 entropy,
        uint256 blockNumber
    );

    event RequestExpired(
        bytes32 indexed requestId,
        address indexed requester,
        uint256 blockNumber
    );

    /*//////////////////////////////////////////////////////////////
                            REQUEST FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Request randomness with default configuration
     * @param seed User-provided seed for additional entropy
     * @return requestId Unique identifier for the request
     */
    function requestRandomness(
        uint256 seed
    ) external payable returns (bytes32 requestId);

    /**
     * @notice Request randomness with custom configuration
     * @param seed User-provided seed for additional entropy
     * @param config Custom configuration for the request
     * @return requestId Unique identifier for the request
     */
    function requestRandomnessWithConfig(
        uint256 seed,
        CommitRevealConfig calldata config
    ) external payable returns (bytes32 requestId);

    /**
     * @notice Fulfill a randomness request after reveal period
     * @param requestId The request ID to fulfill
     * @return randomness The generated random number
     */
    function fulfillRandomness(
        bytes32 requestId
    ) external returns (uint256 randomness);

    /**
     * @notice Generate randomness with immediate fulfillment (less secure)
     * @param seed User-provided seed
     * @return randomness Generated random number
     * @dev Uses previous block hash, vulnerable to miner manipulation
     */
    function getInstantRandomness(
        uint256 seed
    ) external view returns (uint256 randomness);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get details of a randomness request
     * @param requestId Request identifier
     * @return request Full request details
     */
    function getRequest(
        bytes32 requestId
    ) external view returns (RandomRequest memory request);

    /**
     * @notice Check if a request is ready for fulfillment
     * @param requestId Request identifier
     * @return isReady Whether request can be fulfilled
     * @return blocksRemaining Blocks remaining before reveal (if not ready)
     */
    function isRequestReady(
        bytes32 requestId
    ) external view returns (bool isReady, uint256 blocksRemaining);

    /**
     * @notice Check if a request has expired
     * @param requestId Request identifier
     * @return isExpired Whether request has expired
     */
    function isRequestExpired(
        bytes32 requestId
    ) external view returns (bool isExpired);

    /**
     * @notice Get current configuration
     * @return config Current default configuration
     */
    function getDefaultConfig()
        external
        view
        returns (CommitRevealConfig memory config);

    /**
     * @notice Get required fee for randomness request
     * @return fee Fee amount in wei
     */
    function getRequestFee() external view returns (uint256 fee);

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update default configuration (admin only)
     * @param newConfig New default configuration
     */
    function updateDefaultConfig(
        CommitRevealConfig calldata newConfig
    ) external;

    /**
     * @notice Update request fee (admin only)
     * @param newFee New fee amount
     */
    function updateRequestFee(uint256 newFee) external;

    /**
     * @notice Clean up expired requests to save gas
     * @param requestIds Array of expired request IDs to clean
     */
    function cleanupExpiredRequests(bytes32[] calldata requestIds) external;
}

/**
 * @title SecureRandomConstants
 * @notice Constants for secure random number generation
 */
library SecureRandomConstants {
    /// @notice Default minimum delay between commit and reveal (blocks)
    uint256 public constant DEFAULT_MIN_DELAY = 5; // ~75 seconds on Flare

    /// @notice Default maximum delay before request expires (blocks)
    uint256 public constant DEFAULT_MAX_DELAY = 200; // ~50 minutes on Flare

    /// @notice Minimum possible delay (security requirement)
    uint256 public constant MIN_POSSIBLE_DELAY = 3;

    /// @notice Maximum possible delay (prevent indefinite storage)
    uint256 public constant MAX_POSSIBLE_DELAY = 1000; // ~4 hours on Flare

    /// @notice Default request fee (0.001 FLR)
    uint256 public constant DEFAULT_REQUEST_FEE = 0.001 ether;

    /// @notice Maximum seed value to prevent overflow
    uint256 public constant MAX_SEED_VALUE = type(uint256).max;

    /// @notice Block time on Flare (approximately 1.5 seconds)
    uint256 public constant FLARE_BLOCK_TIME = 1500; // milliseconds
}

/**
 * @title RandomnessLib
 * @notice Library for randomness generation utilities
 */
library RandomnessLib {
    /**
     * @notice Generate secure randomness using commit-reveal with block entropy
     * @param seed User-provided seed
     * @param requester Address of the requesting contract
     * @param blockHash Future block hash for entropy
     * @param consensusEntropy Optional consensus entropy
     * @return randomness Generated random number
     */
    function generateSecureRandomness(
        uint256 seed,
        address requester,
        bytes32 blockHash,
        bytes32 consensusEntropy
    ) internal pure returns (uint256 randomness) {
        // Combine all entropy sources
        bytes32 combined = keccak256(
            abi.encodePacked(seed, requester, blockHash, consensusEntropy)
        );

        return uint256(combined);
    }

    /**
     * @notice Generate random number in a specific range
     * @param randomValue Base random value
     * @param min Minimum value (inclusive)
     * @param max Maximum value (exclusive)
     * @return Random number in range [min, max)
     */
    function randomInRange(
        uint256 randomValue,
        uint256 min,
        uint256 max
    ) internal pure returns (uint256) {
        require(max > min, "Invalid range");
        return min + (randomValue % (max - min));
    }

    /**
     * @notice Generate random boolean
     * @param randomValue Base random value
     * @return Random boolean
     */
    function randomBool(uint256 randomValue) internal pure returns (bool) {
        return randomValue % 2 == 1;
    }

    /**
     * @notice Generate random bytes
     * @param randomValue Base random value
     * @param length Desired length of random bytes
     * @return Random bytes array
     */
    function randomBytes(
        uint256 randomValue,
        uint256 length
    ) internal pure returns (bytes memory) {
        bytes memory result = new bytes(length);
        uint256 remaining = randomValue;

        for (uint256 i = 0; i < length; i++) {
            result[i] = bytes1(uint8(remaining % 256));
            remaining = remaining / 256;
            if (remaining == 0) {
                remaining = uint256(keccak256(abi.encode(randomValue, i)));
            }
        }

        return result;
    }

    /**
     * @notice Generate weighted random choice
     * @param randomValue Base random value
     * @param weights Array of weights for each choice
     * @return index Index of chosen option
     */
    function weightedRandom(
        uint256 randomValue,
        uint256[] memory weights
    ) internal pure returns (uint256 index) {
        require(weights.length > 0, "Empty weights array");

        uint256 totalWeight = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            totalWeight += weights[i];
        }
        require(totalWeight > 0, "Total weight must be positive");

        uint256 randomWeight = randomValue % totalWeight;
        uint256 cumulativeWeight = 0;

        for (uint256 i = 0; i < weights.length; i++) {
            cumulativeWeight += weights[i];
            if (randomWeight < cumulativeWeight) {
                return i;
            }
        }

        // Should never reach here, but return last index as fallback
        return weights.length - 1;
    }
}
