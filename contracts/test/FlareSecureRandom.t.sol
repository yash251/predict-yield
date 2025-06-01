// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FlareSecureRandom.sol";
import "../src/interfaces/ISecureRandom.sol";

/**
 * @title MockRandomRequester
 * @notice Mock contract for testing randomness callbacks
 */
contract MockRandomRequester is ISecureRandomRequester {
    bytes32 public lastRequestId;
    uint256 public lastRandomness;
    bool public callbackReceived;
    bool public shouldRevert;

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function fulfillRandomness(
        bytes32 requestId,
        uint256 randomness
    ) external override {
        if (shouldRevert) {
            revert("Callback intentionally reverted");
        }

        lastRequestId = requestId;
        lastRandomness = randomness;
        callbackReceived = true;
    }

    function reset() external {
        callbackReceived = false;
        lastRandomness = 0;
        lastRequestId = bytes32(0);
    }
}

/**
 * @title FlareSecureRandomTest
 * @notice Test suite for FlareSecureRandom contract
 */
contract FlareSecureRandomTest is Test {
    FlareSecureRandom public secureRandom;
    MockFlareEntropy public mockEntropy;
    MockRandomRequester public mockRequester;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    uint256 constant TEST_SEED = 12345;
    uint256 constant DEFAULT_FEE = 0.001 ether;

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

    function setUp() public {
        // Deploy mock entropy source
        mockEntropy = new MockFlareEntropy();

        // Deploy secure random contract
        vm.prank(owner);
        secureRandom = new FlareSecureRandom(address(mockEntropy), owner);

        // Deploy mock requester
        mockRequester = new MockRandomRequester();

        // Fund test accounts
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(address(mockRequester), 10 ether);

        // Setup mock entropy data
        mockEntropy.setConsensusEntropy(
            1000,
            keccak256("consensus-entropy"),
            true
        );
        mockEntropy.setConsensusEntropy(
            1001,
            keccak256("consensus-entropy-2"),
            true
        );
    }

    /*//////////////////////////////////////////////////////////////
                           DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testDeployment() public {
        assertEq(address(secureRandom.flareEntropy()), address(mockEntropy));
        assertEq(secureRandom.owner(), owner);

        ISecureRandom.CommitRevealConfig memory config = secureRandom
            .getDefaultConfig();
        assertEq(config.minDelay, SecureRandomConstants.DEFAULT_MIN_DELAY);
        assertEq(config.maxDelay, SecureRandomConstants.DEFAULT_MAX_DELAY);
        assertEq(config.commitFee, SecureRandomConstants.DEFAULT_REQUEST_FEE);
        assertTrue(config.useConsensusEntropy);
        assertEq(config.consensusRound, 0);
    }

    function testInitialState() public {
        assertEq(secureRandom.requestCounter(), 1);
        assertEq(secureRandom.collectedFees(), 0);
        assertEq(secureRandom.getRequestFee(), DEFAULT_FEE);
    }

    /*//////////////////////////////////////////////////////////////
                         RANDOMNESS REQUEST TESTS
    //////////////////////////////////////////////////////////////*/

    function testRequestRandomness() public {
        uint256 balanceBefore = user1.balance;

        // Don't check specific requestId, just check the event parameters we care about
        vm.expectEmit(false, true, false, false);
        emit RandomnessRequested(
            bytes32(0), // Will be ignored due to first false in expectEmit
            user1,
            TEST_SEED,
            block.number,
            block.number + 5
        );

        vm.prank(user1);
        bytes32 requestId = secureRandom.requestRandomness{value: DEFAULT_FEE}(
            TEST_SEED
        );

        assertNotEq(requestId, bytes32(0));
        assertEq(user1.balance, balanceBefore - DEFAULT_FEE);
        assertEq(secureRandom.collectedFees(), DEFAULT_FEE);

        ISecureRandom.RandomRequest memory request = secureRandom.getRequest(
            requestId
        );
        assertEq(request.requester, user1);
        assertEq(request.seed, TEST_SEED);
        assertEq(request.commitBlock, block.number);
        assertEq(request.revealBlock, block.number + 5);
        assertFalse(request.fulfilled);
        assertEq(request.randomness, 0);
    }

    function testRequestRandomnessWithCustomConfig() public {
        ISecureRandom.CommitRevealConfig memory customConfig = ISecureRandom
            .CommitRevealConfig({
                minDelay: 10,
                maxDelay: 100,
                commitFee: 0.002 ether,
                useConsensusEntropy: false,
                consensusRound: 1001
            });

        vm.prank(user1);
        bytes32 requestId = secureRandom.requestRandomnessWithConfig{
            value: 0.002 ether
        }(TEST_SEED, customConfig);

        ISecureRandom.RandomRequest memory request = secureRandom.getRequest(
            requestId
        );
        assertEq(request.minDelay, 10);
        assertEq(request.maxDelay, 100);
        assertEq(request.revealBlock, block.number + 10);
    }

    function testRequestRandomnessFailures() public {
        // Test insufficient fee
        vm.prank(user1);
        vm.expectRevert("Insufficient fee");
        secureRandom.requestRandomness{value: DEFAULT_FEE - 1}(TEST_SEED);

        // Test zero seed
        vm.prank(user1);
        vm.expectRevert("Seed must be non-zero");
        secureRandom.requestRandomness{value: DEFAULT_FEE}(0);

        // Test invalid config - min delay too small
        ISecureRandom.CommitRevealConfig memory invalidConfig = ISecureRandom
            .CommitRevealConfig({
                minDelay: 1,
                maxDelay: 100,
                commitFee: DEFAULT_FEE,
                useConsensusEntropy: true,
                consensusRound: 0
            });

        vm.prank(user1);
        vm.expectRevert("Min delay too small");
        secureRandom.requestRandomnessWithConfig{value: DEFAULT_FEE}(
            TEST_SEED,
            invalidConfig
        );
    }

    /*//////////////////////////////////////////////////////////////
                         RANDOMNESS FULFILLMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testFulfillRandomness() public {
        // Request randomness
        vm.prank(user1);
        bytes32 requestId = secureRandom.requestRandomness{value: DEFAULT_FEE}(
            TEST_SEED
        );

        // Fast forward past reveal block
        vm.roll(block.number + 10);

        // Set mock block entropy
        vm.mockCall(
            address(mockEntropy),
            abi.encodeWithSelector(MockFlareEntropy.getBlockEntropy.selector),
            abi.encode(keccak256("test-entropy"), block.timestamp)
        );

        vm.expectEmit(true, true, false, false);
        emit RandomnessFulfilled(requestId, user1, 0, bytes32(0), block.number);

        vm.prank(user2);
        uint256 randomness = secureRandom.fulfillRandomness(requestId);

        assertGt(randomness, 0);

        ISecureRandom.RandomRequest memory request = secureRandom.getRequest(
            requestId
        );
        assertTrue(request.fulfilled);
        assertEq(request.randomness, randomness);
        assertNotEq(request.entropy, bytes32(0));
    }

    function testFulfillRandomnessWithCallback() public {
        // Request randomness from mock requester contract
        vm.prank(address(mockRequester));
        bytes32 requestId = secureRandom.requestRandomness{value: DEFAULT_FEE}(
            TEST_SEED
        );

        // Fast forward past reveal block
        vm.roll(block.number + 10);

        // Fulfill randomness
        vm.prank(user1);
        uint256 randomness = secureRandom.fulfillRandomness(requestId);

        // Check callback was received
        assertTrue(mockRequester.callbackReceived());
        assertEq(mockRequester.lastRequestId(), requestId);
        assertEq(mockRequester.lastRandomness(), randomness);
    }

    function testFulfillRandomnessCallbackFailure() public {
        // Request randomness from mock requester contract
        vm.prank(address(mockRequester));
        bytes32 requestId = secureRandom.requestRandomness{value: DEFAULT_FEE}(
            TEST_SEED
        );

        // Set callback to revert
        mockRequester.setShouldRevert(true);

        // Fast forward past reveal block
        vm.roll(block.number + 10);

        // Fulfill randomness - should not revert even if callback fails
        vm.prank(user1);
        uint256 randomness = secureRandom.fulfillRandomness(requestId);

        assertGt(randomness, 0);
        assertFalse(mockRequester.callbackReceived()); // Callback should have failed
    }

    function testFulfillRandomnessFailures() public {
        // Request randomness
        vm.prank(user1);
        bytes32 requestId = secureRandom.requestRandomness{value: DEFAULT_FEE}(
            TEST_SEED
        );

        // Test fulfilling before reveal block
        vm.prank(user1);
        vm.expectRevert("Request not ready for reveal");
        secureRandom.fulfillRandomness(requestId);

        // Fast forward past reveal block
        vm.roll(block.number + 10);

        // Fulfill once
        vm.prank(user1);
        secureRandom.fulfillRandomness(requestId);

        // Test fulfilling again
        vm.prank(user1);
        vm.expectRevert("Request already fulfilled");
        secureRandom.fulfillRandomness(requestId);

        // Test non-existent request
        vm.prank(user1);
        vm.expectRevert("Request does not exist");
        secureRandom.fulfillRandomness(keccak256("fake-request"));
    }

    function testRequestExpiration() public {
        // Request randomness
        vm.prank(user1);
        bytes32 requestId = secureRandom.requestRandomness{value: DEFAULT_FEE}(
            TEST_SEED
        );

        // Fast forward past expiration
        vm.roll(block.number + 300); // Beyond max delay

        // Try to fulfill expired request
        vm.prank(user1);
        vm.expectRevert("Request has expired");
        secureRandom.fulfillRandomness(requestId);

        // Check expiration status
        assertTrue(secureRandom.isRequestExpired(requestId));
    }

    /*//////////////////////////////////////////////////////////////
                           INSTANT RANDOMNESS TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetInstantRandomness() public {
        vm.prank(user1);
        uint256 randomness = secureRandom.getInstantRandomness(TEST_SEED);

        assertGt(randomness, 0);

        // Different seeds should give different results
        vm.prank(user1);
        uint256 randomness2 = secureRandom.getInstantRandomness(TEST_SEED + 1);

        assertNotEq(randomness, randomness2);
    }

    function testInstantRandomnessFailures() public {
        vm.prank(user1);
        vm.expectRevert("Seed must be non-zero");
        secureRandom.getInstantRandomness(0);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testIsRequestReady() public {
        vm.prank(user1);
        bytes32 requestId = secureRandom.requestRandomness{value: DEFAULT_FEE}(
            TEST_SEED
        );

        // Check not ready initially
        (bool isReady, uint256 blocksRemaining) = secureRandom.isRequestReady(
            requestId
        );
        assertFalse(isReady);
        assertEq(blocksRemaining, 5);

        // Fast forward to reveal block
        vm.roll(block.number + 5);

        (isReady, blocksRemaining) = secureRandom.isRequestReady(requestId);
        assertTrue(isReady);
        assertEq(blocksRemaining, 0);
    }

    function testGetRequest() public {
        vm.prank(user1);
        bytes32 requestId = secureRandom.requestRandomness{value: DEFAULT_FEE}(
            TEST_SEED
        );

        ISecureRandom.RandomRequest memory request = secureRandom.getRequest(
            requestId
        );
        assertEq(request.requester, user1);
        assertEq(request.seed, TEST_SEED);
        assertFalse(request.fulfilled);

        // Test non-existent request
        vm.expectRevert("Request does not exist");
        secureRandom.getRequest(keccak256("fake"));
    }

    /*//////////////////////////////////////////////////////////////
                            UTILITY FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testUtilityFunctions() public {
        // Request and fulfill randomness
        vm.prank(user1);
        bytes32 requestId = secureRandom.requestRandomness{value: DEFAULT_FEE}(
            TEST_SEED
        );

        vm.roll(block.number + 10);
        vm.prank(user1);
        secureRandom.fulfillRandomness(requestId);

        // Test random in range
        uint256 randomInRange = secureRandom.getRandomInRange(
            requestId,
            1,
            100
        );
        assertGe(randomInRange, 1);
        assertLt(randomInRange, 100);

        // Test random boolean
        bool randomBool = secureRandom.getRandomBool(requestId);
        // Just check it doesn't revert

        // Test weighted random
        uint256[] memory weights = new uint256[](3);
        weights[0] = 10;
        weights[1] = 20;
        weights[2] = 30;

        uint256 choice = secureRandom.getWeightedRandom(requestId, weights);
        assertLt(choice, 3);
    }

    function testUtilityFunctionFailures() public {
        vm.prank(user1);
        bytes32 requestId = secureRandom.requestRandomness{value: DEFAULT_FEE}(
            TEST_SEED
        );

        // Test unfulfilled request
        vm.expectRevert("Request not fulfilled");
        secureRandom.getRandomInRange(requestId, 1, 100);

        vm.expectRevert("Request not fulfilled");
        secureRandom.getRandomBool(requestId);

        uint256[] memory weights = new uint256[](1);
        weights[0] = 10;
        vm.expectRevert("Request not fulfilled");
        secureRandom.getWeightedRandom(requestId, weights);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testUpdateDefaultConfig() public {
        ISecureRandom.CommitRevealConfig memory newConfig = ISecureRandom
            .CommitRevealConfig({
                minDelay: 10,
                maxDelay: 500,
                commitFee: 0.005 ether,
                useConsensusEntropy: false,
                consensusRound: 1001
            });

        vm.prank(owner);
        secureRandom.updateDefaultConfig(newConfig);

        ISecureRandom.CommitRevealConfig memory updatedConfig = secureRandom
            .getDefaultConfig();
        assertEq(updatedConfig.minDelay, 10);
        assertEq(updatedConfig.maxDelay, 500);
        assertEq(updatedConfig.commitFee, 0.005 ether);
        assertFalse(updatedConfig.useConsensusEntropy);
        assertEq(updatedConfig.consensusRound, 1001);
    }

    function testUpdateRequestFee() public {
        vm.prank(owner);
        secureRandom.updateRequestFee(0.002 ether);

        assertEq(secureRandom.getRequestFee(), 0.002 ether);
    }

    function testWithdrawFees() public {
        // Generate some fees
        vm.prank(user1);
        secureRandom.requestRandomness{value: DEFAULT_FEE}(TEST_SEED);

        vm.prank(user2);
        secureRandom.requestRandomness{value: DEFAULT_FEE}(TEST_SEED + 1);

        uint256 totalFees = 2 * DEFAULT_FEE;
        assertEq(secureRandom.collectedFees(), totalFees);

        address payable recipient = payable(address(0x999));
        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(owner);
        secureRandom.withdrawFees(recipient);

        assertEq(recipient.balance, recipientBalanceBefore + totalFees);
        assertEq(secureRandom.collectedFees(), 0);
    }

    function testCleanupExpiredRequests() public {
        // Create multiple requests
        vm.prank(user1);
        bytes32 requestId1 = secureRandom.requestRandomness{value: DEFAULT_FEE}(
            TEST_SEED
        );

        vm.prank(user2);
        bytes32 requestId2 = secureRandom.requestRandomness{value: DEFAULT_FEE}(
            TEST_SEED + 1
        );

        // Fast forward past expiration
        vm.roll(block.number + 300);

        bytes32[] memory expiredIds = new bytes32[](2);
        expiredIds[0] = requestId1;
        expiredIds[1] = requestId2;

        vm.prank(user1);
        secureRandom.cleanupExpiredRequests(expiredIds);

        // Verify requests are cleaned up
        vm.expectRevert("Request does not exist");
        secureRandom.getRequest(requestId1);

        vm.expectRevert("Request does not exist");
        secureRandom.getRequest(requestId2);
    }

    function testAdminAccessControl() public {
        ISecureRandom.CommitRevealConfig memory config = secureRandom
            .getDefaultConfig();

        // Test non-owner cannot update config
        vm.prank(user1);
        vm.expectRevert();
        secureRandom.updateDefaultConfig(config);

        // Test non-owner cannot update fee
        vm.prank(user1);
        vm.expectRevert();
        secureRandom.updateRequestFee(0.002 ether);

        // Test non-owner cannot withdraw fees
        vm.prank(user1);
        vm.expectRevert();
        secureRandom.withdrawFees(payable(user1));
    }

    /*//////////////////////////////////////////////////////////////
                         RANDOMNESS LIBRARY TESTS
    //////////////////////////////////////////////////////////////*/

    function testRandomnessLibrary() public {
        uint256 randomValue = 123456789;

        // Test random in range
        uint256 inRange = RandomnessLib.randomInRange(randomValue, 10, 20);
        assertGe(inRange, 10);
        assertLt(inRange, 20);

        // Test random boolean
        bool randomBool = RandomnessLib.randomBool(randomValue);
        // Just verify it compiles and runs

        // Test random bytes
        bytes memory randomBytes = RandomnessLib.randomBytes(randomValue, 10);
        assertEq(randomBytes.length, 10);

        // Test weighted random
        uint256[] memory weights = new uint256[](3);
        weights[0] = 25;
        weights[1] = 50;
        weights[2] = 25;

        uint256 choice = RandomnessLib.weightedRandom(randomValue, weights);
        assertLt(choice, 3);
    }

    function testRandomnessLibraryEdgeCases() public {
        uint256[] memory emptyWeights = new uint256[](0);

        vm.expectRevert("Empty weights array");
        RandomnessLib.weightedRandom(123, emptyWeights);

        uint256[] memory zeroWeights = new uint256[](2);
        zeroWeights[0] = 0;
        zeroWeights[1] = 0;

        vm.expectRevert("Total weight must be positive");
        RandomnessLib.weightedRandom(123, zeroWeights);

        vm.expectRevert("Invalid range");
        RandomnessLib.randomInRange(123, 10, 10);

        vm.expectRevert("Invalid range");
        RandomnessLib.randomInRange(123, 20, 10);
    }

    /*//////////////////////////////////////////////////////////////
                         INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testFullRandomnessFlow() public {
        // Step 1: Request randomness
        vm.prank(user1);
        bytes32 requestId = secureRandom.requestRandomness{value: DEFAULT_FEE}(
            TEST_SEED
        );

        // Step 2: Check request status
        (bool isReady, ) = secureRandom.isRequestReady(requestId);
        assertFalse(isReady);

        // Step 3: Wait for reveal block
        vm.roll(block.number + 10);

        (isReady, ) = secureRandom.isRequestReady(requestId);
        assertTrue(isReady);

        // Step 4: Fulfill randomness
        vm.prank(user2);
        uint256 randomness = secureRandom.fulfillRandomness(requestId);
        assertGt(randomness, 0);

        // Step 5: Use utility functions
        uint256 diceRoll = secureRandom.getRandomInRange(requestId, 1, 7);
        assertGe(diceRoll, 1);
        assertLe(diceRoll, 6);

        bool coinFlip = secureRandom.getRandomBool(requestId);
        // Verify it doesn't revert

        // Step 6: Verify request is fulfilled
        ISecureRandom.RandomRequest memory request = secureRandom.getRequest(
            requestId
        );
        assertTrue(request.fulfilled);
        assertEq(request.randomness, randomness);
    }

    function testMultipleConcurrentRequests() public {
        uint256 numRequests = 5;
        bytes32[] memory requestIds = new bytes32[](numRequests);

        // Create multiple requests
        for (uint256 i = 0; i < numRequests; i++) {
            vm.prank(user1);
            requestIds[i] = secureRandom.requestRandomness{value: DEFAULT_FEE}(
                TEST_SEED + i
            );
        }

        // Fast forward
        vm.roll(block.number + 10);

        // Fulfill all requests
        for (uint256 i = 0; i < numRequests; i++) {
            vm.prank(user2);
            uint256 randomness = secureRandom.fulfillRandomness(requestIds[i]);
            assertGt(randomness, 0);

            // Verify each request has different randomness
            for (uint256 j = 0; j < i; j++) {
                ISecureRandom.RandomRequest memory prevRequest = secureRandom
                    .getRequest(requestIds[j]);
                assertNotEq(randomness, prevRequest.randomness);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _createAndFulfillRequest(
        uint256 seed
    ) internal returns (bytes32 requestId, uint256 randomness) {
        vm.prank(user1);
        requestId = secureRandom.requestRandomness{value: DEFAULT_FEE}(seed);

        vm.roll(block.number + 10);

        vm.prank(user2);
        randomness = secureRandom.fulfillRandomness(requestId);
    }
}
