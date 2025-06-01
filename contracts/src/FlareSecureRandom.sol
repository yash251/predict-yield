// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/ISecureRandom.sol";

/**
 * @title MockFlareEntropy
 * @notice Mock implementation of Flare's entropy sources for testing
 * @dev In production, this would interface with actual Flare consensus
 */
contract MockFlareEntropy is IFlareEntropy {
    mapping(uint256 => bytes32) public blockEntropies;
    mapping(uint256 => bytes32) public consensusEntropies;
    mapping(uint256 => bool) public finalizedRounds;

    uint256 public currentRound = 1000;

    function setBlockEntropy(uint256 blockNumber, bytes32 entropy) external {
        blockEntropies[blockNumber] = entropy;
    }

    function setConsensusEntropy(
        uint256 round,
        bytes32 entropy,
        bool finalized
    ) external {
        consensusEntropies[round] = entropy;
        finalizedRounds[round] = finalized;
    }

    function getBlockEntropy(
        uint256 blockNumber
    ) external view override returns (bytes32 entropy, uint256 timestamp) {
        if (blockEntropies[blockNumber] != bytes32(0)) {
            entropy = blockEntropies[blockNumber];
        } else {
            entropy = blockhash(blockNumber);
        }
        timestamp = block.timestamp;
    }

    function getConsensusEntropy(
        uint256 round
    ) external view override returns (bytes32 entropy, bool isFinalized) {
        entropy = consensusEntropies[round];
        isFinalized = finalizedRounds[round];
    }

    function getCurrentRound() external view override returns (uint256 round) {
        return currentRound;
    }

    function setCurrentRound(uint256 round) external {
        currentRound = round;
    }
}

/**
 * @title FlareSecureRandom
 * @notice Secure random number generation for Flare Network
 * @dev Implements commit-reveal scheme with block-based and consensus entropy
 */
contract FlareSecureRandom is ISecureRandom, Ownable, ReentrancyGuard {
    using RandomnessLib for uint256;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Flare entropy source interface
    IFlareEntropy public flareEntropy;

    /// @notice Default configuration for randomness requests
    CommitRevealConfig public defaultConfig;

    /// @notice Mapping of request ID to request details
    mapping(bytes32 => RandomRequest) public requests;

    /// @notice Mapping to check if request ID exists
    mapping(bytes32 => bool) public requestExists;

    /// @notice Request counter for generating unique IDs
    uint256 public requestCounter;

    /// @notice Total collected fees
    uint256 public collectedFees;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event ConfigUpdated(
        uint256 minDelay,
        uint256 maxDelay,
        uint256 commitFee,
        bool useConsensusEntropy
    );

    event FeesWithdrawn(address indexed recipient, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier validSeed(uint256 seed) {
        require(seed > 0, "Seed must be non-zero");
        require(seed <= SecureRandomConstants.MAX_SEED_VALUE, "Seed too large");
        _;
    }

    modifier requestExist(bytes32 requestId) {
        require(requestExists[requestId], "Request does not exist");
        _;
    }

    modifier notFulfilled(bytes32 requestId) {
        require(!requests[requestId].fulfilled, "Request already fulfilled");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _flareEntropy,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_flareEntropy != address(0), "Invalid entropy address");

        flareEntropy = IFlareEntropy(_flareEntropy);

        // Set default configuration
        defaultConfig = CommitRevealConfig({
            minDelay: SecureRandomConstants.DEFAULT_MIN_DELAY,
            maxDelay: SecureRandomConstants.DEFAULT_MAX_DELAY,
            commitFee: SecureRandomConstants.DEFAULT_REQUEST_FEE,
            useConsensusEntropy: true,
            consensusRound: 0 // 0 means use current round
        });

        requestCounter = 1;
    }

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
    )
        external
        payable
        override
        validSeed(seed)
        nonReentrant
        returns (bytes32 requestId)
    {
        return _requestRandomnessInternal(seed, defaultConfig);
    }

    /**
     * @notice Request randomness with custom configuration
     * @param seed User-provided seed for additional entropy
     * @param config Custom configuration for the request
     * @return requestId Unique identifier for the request
     */
    function requestRandomnessWithConfig(
        uint256 seed,
        CommitRevealConfig calldata config
    )
        external
        payable
        override
        validSeed(seed)
        nonReentrant
        returns (bytes32 requestId)
    {
        _validateConfig(config);
        return _requestRandomnessInternal(seed, config);
    }

    /**
     * @notice Fulfill a randomness request after reveal period
     * @param requestId The request ID to fulfill
     * @return randomness The generated random number
     */
    function fulfillRandomness(
        bytes32 requestId
    )
        external
        override
        requestExist(requestId)
        notFulfilled(requestId)
        nonReentrant
        returns (uint256 randomness)
    {
        RandomRequest storage request = requests[requestId];

        // Check if request is ready
        require(
            block.number >= request.revealBlock,
            "Request not ready for reveal"
        );

        // Check if request has expired
        require(
            block.number <= request.commitBlock + request.maxDelay,
            "Request has expired"
        );

        // Get entropy sources
        bytes32 blockEntropy = blockhash(request.revealBlock);
        if (blockEntropy == bytes32(0)) {
            // Use more recent block if reveal block is too old
            blockEntropy = blockhash(block.number - 1);
        }

        bytes32 consensusEntropy = bytes32(0);
        if (defaultConfig.useConsensusEntropy) {
            uint256 round = defaultConfig.consensusRound;
            if (round == 0) {
                round = flareEntropy.getCurrentRound();
            }
            (consensusEntropy, ) = flareEntropy.getConsensusEntropy(round);
        }

        // Generate secure randomness
        randomness = RandomnessLib.generateSecureRandomness(
            request.seed,
            request.requester,
            blockEntropy,
            consensusEntropy
        );

        // Add additional entropy sources
        randomness = uint256(
            keccak256(
                abi.encodePacked(
                    randomness,
                    block.difficulty,
                    block.timestamp,
                    request.commitBlock
                )
            )
        );

        // Update request
        request.fulfilled = true;
        request.randomness = randomness;
        request.entropy = blockEntropy;

        emit RandomnessFulfilled(
            requestId,
            request.requester,
            randomness,
            blockEntropy,
            block.number
        );

        // Callback to requester if it's a contract
        if (request.requester.code.length > 0) {
            try
                ISecureRandomRequester(request.requester).fulfillRandomness(
                    requestId,
                    randomness
                )
            {} catch {
                // Ignore callback failures to prevent blocking
            }
        }

        return randomness;
    }

    /**
     * @notice Generate randomness with immediate fulfillment (less secure)
     * @param seed User-provided seed
     * @return randomness Generated random number
     * @dev Uses previous block hash, vulnerable to miner manipulation
     */
    function getInstantRandomness(
        uint256 seed
    ) external view override validSeed(seed) returns (uint256 randomness) {
        bytes32 blockEntropy = blockhash(block.number - 1);

        bytes32 consensusEntropy = bytes32(0);
        if (defaultConfig.useConsensusEntropy) {
            uint256 round = flareEntropy.getCurrentRound();
            (consensusEntropy, ) = flareEntropy.getConsensusEntropy(round);
        }

        // Add additional entropy for instant randomness
        uint256 baseRandomness = RandomnessLib.generateSecureRandomness(
            seed,
            msg.sender,
            blockEntropy,
            consensusEntropy
        );

        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        baseRandomness,
                        block.difficulty,
                        block.timestamp,
                        block.number
                    )
                )
            );
    }

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
    ) external view override returns (RandomRequest memory request) {
        require(requestExists[requestId], "Request does not exist");
        return requests[requestId];
    }

    /**
     * @notice Check if a request is ready for fulfillment
     * @param requestId Request identifier
     * @return isReady Whether request can be fulfilled
     * @return blocksRemaining Blocks remaining before reveal (if not ready)
     */
    function isRequestReady(
        bytes32 requestId
    ) external view override returns (bool isReady, uint256 blocksRemaining) {
        require(requestExists[requestId], "Request does not exist");

        RandomRequest memory request = requests[requestId];

        if (block.number >= request.revealBlock) {
            isReady = true;
            blocksRemaining = 0;
        } else {
            isReady = false;
            blocksRemaining = request.revealBlock - block.number;
        }
    }

    /**
     * @notice Check if a request has expired
     * @param requestId Request identifier
     * @return isExpired Whether request has expired
     */
    function isRequestExpired(
        bytes32 requestId
    ) external view override returns (bool isExpired) {
        require(requestExists[requestId], "Request does not exist");

        RandomRequest memory request = requests[requestId];
        return block.number > request.commitBlock + request.maxDelay;
    }

    /**
     * @notice Get current configuration
     * @return config Current default configuration
     */
    function getDefaultConfig()
        external
        view
        override
        returns (CommitRevealConfig memory config)
    {
        return defaultConfig;
    }

    /**
     * @notice Get required fee for randomness request
     * @return fee Fee amount in wei
     */
    function getRequestFee() external view override returns (uint256 fee) {
        return defaultConfig.commitFee;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update default configuration
     * @param newConfig New default configuration
     */
    function updateDefaultConfig(
        CommitRevealConfig calldata newConfig
    ) external override onlyOwner {
        _validateConfig(newConfig);
        defaultConfig = newConfig;

        emit ConfigUpdated(
            newConfig.minDelay,
            newConfig.maxDelay,
            newConfig.commitFee,
            newConfig.useConsensusEntropy
        );
    }

    /**
     * @notice Update request fee
     * @param newFee New fee amount
     */
    function updateRequestFee(uint256 newFee) external override onlyOwner {
        defaultConfig.commitFee = newFee;
    }

    /**
     * @notice Clean up expired requests to save gas
     * @param requestIds Array of expired request IDs to clean
     */
    function cleanupExpiredRequests(
        bytes32[] calldata requestIds
    ) external override {
        for (uint256 i = 0; i < requestIds.length; i++) {
            bytes32 requestId = requestIds[i];

            if (requestExists[requestId]) {
                RandomRequest memory request = requests[requestId];

                if (block.number > request.commitBlock + request.maxDelay) {
                    delete requests[requestId];
                    delete requestExists[requestId];

                    emit RequestExpired(
                        requestId,
                        request.requester,
                        block.number
                    );
                }
            }
        }
    }

    /**
     * @notice Withdraw collected fees
     * @param recipient Address to receive fees
     */
    function withdrawFees(address payable recipient) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        uint256 amount = collectedFees;
        require(amount > 0, "No fees to withdraw");

        collectedFees = 0;

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Fee withdrawal failed");

        emit FeesWithdrawn(recipient, amount);
    }

    /**
     * @notice Update Flare entropy source
     * @param newEntropySource New entropy source address
     */
    function updateEntropySource(address newEntropySource) external onlyOwner {
        require(newEntropySource != address(0), "Invalid entropy source");
        flareEntropy = IFlareEntropy(newEntropySource);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal function to create randomness requests
     * @param seed User-provided seed
     * @param config Request configuration
     * @return requestId Generated request ID
     */
    function _requestRandomnessInternal(
        uint256 seed,
        CommitRevealConfig memory config
    ) internal returns (bytes32 requestId) {
        require(msg.value >= config.commitFee, "Insufficient fee");

        // Generate unique request ID
        requestId = keccak256(
            abi.encodePacked(
                msg.sender,
                seed,
                block.number,
                block.timestamp,
                requestCounter++
            )
        );

        // Calculate reveal block
        uint256 revealBlock = block.number + config.minDelay;

        // Create request
        requests[requestId] = RandomRequest({
            requester: msg.sender,
            seed: seed,
            commitBlock: block.number,
            revealBlock: revealBlock,
            minDelay: config.minDelay,
            maxDelay: config.maxDelay,
            fulfilled: false,
            randomness: 0,
            entropy: bytes32(0)
        });

        requestExists[requestId] = true;
        collectedFees += msg.value;

        emit RandomnessRequested(
            requestId,
            msg.sender,
            seed,
            block.number,
            revealBlock
        );

        return requestId;
    }

    /**
     * @notice Validate configuration parameters
     * @param config Configuration to validate
     */
    function _validateConfig(CommitRevealConfig memory config) internal pure {
        require(
            config.minDelay >= SecureRandomConstants.MIN_POSSIBLE_DELAY,
            "Min delay too small"
        );
        require(
            config.maxDelay <= SecureRandomConstants.MAX_POSSIBLE_DELAY,
            "Max delay too large"
        );
        require(config.maxDelay > config.minDelay, "Invalid delay range");
    }

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Generate random number in range for a request
     * @param requestId Request ID containing randomness
     * @param min Minimum value (inclusive)
     * @param max Maximum value (exclusive)
     * @return Random number in range
     */
    function getRandomInRange(
        bytes32 requestId,
        uint256 min,
        uint256 max
    ) external view requestExist(requestId) returns (uint256) {
        RandomRequest memory request = requests[requestId];
        require(request.fulfilled, "Request not fulfilled");

        return request.randomness.randomInRange(min, max);
    }

    /**
     * @notice Generate random boolean for a request
     * @param requestId Request ID containing randomness
     * @return Random boolean
     */
    function getRandomBool(
        bytes32 requestId
    ) external view requestExist(requestId) returns (bool) {
        RandomRequest memory request = requests[requestId];
        require(request.fulfilled, "Request not fulfilled");

        return request.randomness.randomBool();
    }

    /**
     * @notice Generate weighted random choice for a request
     * @param requestId Request ID containing randomness
     * @param weights Array of weights for each choice
     * @return index Index of chosen option
     */
    function getWeightedRandom(
        bytes32 requestId,
        uint256[] calldata weights
    ) external view requestExist(requestId) returns (uint256) {
        RandomRequest memory request = requests[requestId];
        require(request.fulfilled, "Request not fulfilled");

        return request.randomness.weightedRandom(weights);
    }

    /*//////////////////////////////////////////////////////////////
                           FALLBACK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Receive function to accept payments
     */
    receive() external payable {
        // Accept payments for fees
    }
}
