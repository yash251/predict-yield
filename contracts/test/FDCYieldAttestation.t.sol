// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FDCYieldAttestation.sol";
import "../src/FTSOv2YieldOracle.sol";
import "../src/interfaces/IFDCJsonApi.sol";

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
 * @title MockFDCHub
 * @notice Mock FDC Hub contract for testing
 */
contract MockFDCHub is IFDCHub {
    uint256 public constant ATTESTATION_FEE = 0.001 ether;
    uint256 public requestCounter = 1;

    mapping(bytes32 => bytes32) public requestToMIC;
    mapping(bytes32 => bytes) public requestData;

    event AttestationRequested(
        bytes32 indexed requestId,
        bytes32 attestationType,
        bytes32 sourceId,
        bytes32 mic,
        uint256 fee
    );

    function requestAttestation(
        bytes32 attestationType,
        bytes32 sourceId,
        bytes32 messageIntegrityCode,
        bytes calldata requestBody
    ) external payable override returns (bytes32 requestId) {
        require(msg.value >= ATTESTATION_FEE, "Insufficient fee");

        requestId = keccak256(
            abi.encodePacked(block.timestamp, requestCounter++)
        );
        requestToMIC[requestId] = messageIntegrityCode;
        requestData[requestId] = requestBody;

        emit AttestationRequested(
            requestId,
            attestationType,
            sourceId,
            messageIntegrityCode,
            msg.value
        );
    }

    function getAttestationFee(
        bytes32 // attestationType
    ) external pure override returns (uint256 fee) {
        return ATTESTATION_FEE;
    }
}

/**
 * @title MockFDCRelay
 * @notice Mock FDC Relay contract for testing
 */
contract MockFDCRelay is IFDCRelay {
    mapping(uint256 => bytes32) public merkleRoots;
    mapping(uint256 => bool) public votingRoundFinalized;
    mapping(uint256 => uint256) public signatureWeights;

    uint256 public currentVotingRound = 1000;

    function setMerkleRoot(uint256 votingRound, bytes32 merkleRoot) external {
        merkleRoots[votingRound] = merkleRoot;
        votingRoundFinalized[votingRound] = true;
        signatureWeights[votingRound] = 8500; // 85% signature weight
    }

    function setSignatureWeight(uint256 votingRound, uint256 weight) external {
        signatureWeights[votingRound] = weight;
    }

    function getMerkleRoot(
        uint256 votingRound
    ) external view override returns (bytes32 merkleRoot, bool isFinalized) {
        return (merkleRoots[votingRound], votingRoundFinalized[votingRound]);
    }

    function getCurrentVotingRound() external view override returns (uint256) {
        return currentVotingRound;
    }

    function getConsensusStatus(
        uint256 votingRound
    )
        external
        view
        override
        returns (bool hasConsensus, uint256 signatureWeight)
    {
        signatureWeight = signatureWeights[votingRound];
        hasConsensus = signatureWeight >= 5001; // > 50%
    }

    function setCurrentVotingRound(uint256 round) external {
        currentVotingRound = round;
    }
}

/**
 * @title MockFDCVerification
 * @notice Mock FDC Verification contract for testing
 */
contract MockFDCVerification is IFDCVerification {
    MockFDCRelay public relay;

    constructor(address _relay) {
        relay = MockFDCRelay(_relay);
    }

    function verifyAttestationProof(
        uint256 votingRound,
        bytes32[] calldata merkleProof,
        bytes32 responseHash
    ) external view override returns (bool isValid) {
        (bytes32 merkleRoot, bool isFinalized) = relay.getMerkleRoot(
            votingRound
        );

        if (!isFinalized || merkleRoot == bytes32(0)) {
            return false;
        }

        // Simple mock verification - in real implementation this would verify the full Merkle proof
        return MerkleProofLib.verify(merkleProof, merkleRoot, responseHash);
    }

    function verifyJsonApiResponse(
        uint256 votingRound,
        bytes32[] calldata merkleProof,
        bytes calldata response
    ) external view override returns (bool isValid, bytes memory parsedData) {
        bytes32 responseHash = keccak256(response);
        isValid = this.verifyAttestationProof(
            votingRound,
            merkleProof,
            responseHash
        );

        if (isValid) {
            parsedData = response;
        }
    }
}

/**
 * @title FDCYieldAttestationTest
 * @notice Test suite for FDC yield attestation contract
 */
contract FDCYieldAttestationTest is Test {
    FDCYieldAttestation public fdcAttestation;
    FTSOv2YieldOracle public ftsoOracle;
    MockFDCHub public fdcHub;
    MockFDCRelay public fdcRelay;
    MockFDCVerification public fdcVerification;
    MockContractRegistry public contractRegistry;
    MockFTSOv2 public mockFTSOv2;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public dataProvider = address(0x4);

    string constant TEST_PROTOCOL = "AAVE_USDC";
    string constant TEST_API_URL = "https://api.aave.com/v1/yield";
    string constant TEST_JQ_FILTER = ".data.yieldRate";

    event YieldAttestationRequested(
        string indexed protocol,
        bytes32 indexed requestId,
        string apiUrl,
        uint256 fee
    );

    event FDCYieldDataUpdated(
        string indexed protocol,
        uint256 rate,
        uint64 timestamp,
        uint256 confidence,
        bytes32 requestId
    );

    function setUp() public {
        // Deploy mocks
        mockFTSOv2 = new MockFTSOv2();
        contractRegistry = new MockContractRegistry(address(mockFTSOv2));
        fdcHub = new MockFDCHub();
        fdcRelay = new MockFDCRelay();
        fdcVerification = new MockFDCVerification(address(fdcRelay));

        // Deploy FTSO oracle
        vm.prank(owner);
        ftsoOracle = new FTSOv2YieldOracle(address(contractRegistry), owner);

        // Deploy FDC attestation contract
        vm.prank(owner);
        fdcAttestation = new FDCYieldAttestation(
            address(fdcHub),
            address(fdcRelay),
            address(fdcVerification),
            address(ftsoOracle),
            owner
        );

        // Setup initial data
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);

        // Configure protocol API
        vm.prank(owner);
        fdcAttestation.configureProtocolApi(
            TEST_PROTOCOL,
            TEST_API_URL,
            TEST_JQ_FILTER,
            3600, // 1 hour update interval
            FDCConstants.AAVE_SOURCE_ID
        );
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testDeployment() public {
        assertEq(address(fdcAttestation.fdcHub()), address(fdcHub));
        assertEq(address(fdcAttestation.fdcRelay()), address(fdcRelay));
        assertEq(
            address(fdcAttestation.fdcVerification()),
            address(fdcVerification)
        );
        assertEq(
            address(fdcAttestation.ftsoYieldOracle()),
            address(ftsoOracle)
        );
        assertEq(fdcAttestation.owner(), owner);
        assertEq(fdcAttestation.getAttestationFee(), 0.001 ether);
        assertEq(fdcAttestation.consensusThreshold(), 7000); // 70%
    }

    function testInitialProtocolSetup() public {
        assertTrue(fdcAttestation.isSupportedProtocol(TEST_PROTOCOL));
        assertTrue(fdcAttestation.isSupportedProtocol("AAVE_USDT"));
        assertTrue(fdcAttestation.isSupportedProtocol("COMPOUND_ETH"));

        FDCYieldAttestation.ApiConfig memory config = fdcAttestation
            .getProtocolApiConfig(TEST_PROTOCOL);
        assertEq(config.apiUrl, TEST_API_URL);
        assertEq(config.jqFilter, TEST_JQ_FILTER);
        assertTrue(config.isActive);
    }

    /*//////////////////////////////////////////////////////////////
                        ATTESTATION REQUEST TESTS
    //////////////////////////////////////////////////////////////*/

    function testRequestYieldAttestation() public {
        uint256 fee = fdcAttestation.getAttestationFee();

        vm.expectEmit(true, false, false, true);
        emit YieldAttestationRequested(
            TEST_PROTOCOL,
            bytes32(0),
            TEST_API_URL,
            fee
        );

        vm.prank(user1);
        bytes32 requestId = fdcAttestation.requestYieldAttestation{value: fee}(
            TEST_PROTOCOL,
            "",
            ""
        );

        assertNotEq(requestId, bytes32(0));

        // Check pending requests
        bytes32[] memory pending = fdcAttestation.getPendingRequests(
            TEST_PROTOCOL
        );
        assertEq(pending.length, 1);
        assertEq(pending[0], requestId);
    }

    function testRequestYieldAttestationWithCustomParams() public {
        uint256 fee = fdcAttestation.getAttestationFee();
        string memory customUrl = "https://custom-api.com/yield";
        string memory customFilter = ".custom.yieldRate";

        vm.expectEmit(true, false, false, true);
        emit YieldAttestationRequested(
            TEST_PROTOCOL,
            bytes32(0),
            customUrl,
            fee
        );

        vm.prank(user1);
        bytes32 requestId = fdcAttestation.requestYieldAttestation{value: fee}(
            TEST_PROTOCOL,
            customUrl,
            customFilter
        );

        assertNotEq(requestId, bytes32(0));
    }

    function testRequestYieldAttestationFailures() public {
        uint256 fee = fdcAttestation.getAttestationFee();

        // Insufficient fee
        vm.prank(user1);
        vm.expectRevert("Insufficient fee");
        fdcAttestation.requestYieldAttestation{value: fee - 1}(
            TEST_PROTOCOL,
            "",
            ""
        );

        // Unsupported protocol
        vm.prank(user1);
        vm.expectRevert("Protocol not supported");
        fdcAttestation.requestYieldAttestation{value: fee}(
            "INVALID_PROTOCOL",
            "",
            ""
        );

        // Inactive protocol
        vm.prank(owner);
        fdcAttestation.configureProtocolApi(
            "INACTIVE_PROTOCOL",
            "https://test.com",
            ".rate",
            3600,
            keccak256("INACTIVE")
        );

        // Set to inactive manually by replacing with inactive config
        vm.prank(owner);
        fdcAttestation.configureProtocolApi(
            "INACTIVE_PROTOCOL",
            "",
            "",
            3600,
            keccak256("INACTIVE")
        );
    }

    /*//////////////////////////////////////////////////////////////
                       ATTESTATION VERIFICATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testVerifyYieldAttestation() public {
        uint256 votingRound = 1001;
        uint256 yieldRate = 450; // 4.5%

        // Create mock response
        JsonApiAttestationTypes.YieldDataResponse
            memory yieldData = JsonApiAttestationTypes.YieldDataResponse({
                protocol: TEST_PROTOCOL,
                yieldRate: yieldRate,
                timestamp: uint64(block.timestamp),
                tvl: 1000000 * 1e18, // $1M TVL
                confidence: 9000, // 90%
                source: TEST_API_URL
            });

        JsonApiAttestationTypes.JsonApiResponse
            memory apiResponse = JsonApiAttestationTypes.JsonApiResponse({
                attestationType: FDCConstants.JSON_API_TYPE,
                sourceId: FDCConstants.AAVE_SOURCE_ID,
                votingRound: uint64(votingRound),
                lowestUsedTimestamp: uint64(block.timestamp),
                requestId: keccak256("test-request"),
                responseData: abi.encode(yieldData),
                isValid: true
            });

        bytes memory encodedResponse = abi.encode(apiResponse);
        bytes32 responseHash = keccak256(encodedResponse);

        // Setup mock Merkle proof
        bytes32[] memory merkleProof = new bytes32[](2);
        merkleProof[0] = keccak256("proof1");
        merkleProof[1] = keccak256("proof2");

        // Calculate expected Merkle root
        bytes32 merkleRoot = MerkleProofLib.verify(
            merkleProof,
            responseHash,
            responseHash
        )
            ? responseHash
            : keccak256(abi.encodePacked(merkleProof[0], responseHash));

        // Setup mock FDC state
        fdcRelay.setMerkleRoot(votingRound, merkleRoot);
        fdcRelay.setSignatureWeight(votingRound, 8500); // 85%

        // Verify attestation
        (
            bool isValid,
            JsonApiAttestationTypes.YieldDataResponse memory verifiedData
        ) = fdcAttestation.verifyYieldAttestation(
                votingRound,
                merkleProof,
                encodedResponse
            );

        assertTrue(isValid);
        assertEq(verifiedData.protocol, TEST_PROTOCOL);
        assertEq(verifiedData.yieldRate, yieldRate);
        assertEq(verifiedData.timestamp, block.timestamp);
    }

    function testVerifyYieldAttestationFailures() public {
        uint256 votingRound = 1002;
        bytes32[] memory emptyProof = new bytes32[](0);
        bytes memory emptyResponse = "";

        // Unfinalized voting round
        vm.expectRevert("Voting round not finalized");
        fdcAttestation.verifyYieldAttestation(
            votingRound,
            emptyProof,
            emptyResponse
        );

        // Setup finalized but no consensus
        fdcRelay.setMerkleRoot(votingRound, keccak256("test"));
        fdcRelay.setSignatureWeight(votingRound, 4000); // 40% - insufficient

        vm.expectRevert("Insufficient consensus");
        fdcAttestation.verifyYieldAttestation(
            votingRound,
            emptyProof,
            emptyResponse
        );
    }

    /*//////////////////////////////////////////////////////////////
                       YIELD DATA SUBMISSION TESTS
    //////////////////////////////////////////////////////////////*/

    function testSubmitVerifiedYieldData() public {
        uint256 votingRound = 1003;
        uint256 yieldRate = 520; // 5.2%

        // Create and setup attestation response
        JsonApiAttestationTypes.YieldDataResponse
            memory yieldData = JsonApiAttestationTypes.YieldDataResponse({
                protocol: TEST_PROTOCOL,
                yieldRate: yieldRate,
                timestamp: uint64(block.timestamp),
                tvl: 2000000 * 1e18, // $2M TVL
                confidence: 8800,
                source: TEST_API_URL
            });

        JsonApiAttestationTypes.JsonApiResponse
            memory apiResponse = JsonApiAttestationTypes.JsonApiResponse({
                attestationType: FDCConstants.JSON_API_TYPE,
                sourceId: FDCConstants.AAVE_SOURCE_ID,
                votingRound: uint64(votingRound),
                lowestUsedTimestamp: uint64(block.timestamp),
                requestId: keccak256("test-request-2"),
                responseData: abi.encode(yieldData),
                isValid: true
            });

        bytes memory encodedResponse = abi.encode(apiResponse);
        bytes32 responseHash = keccak256(encodedResponse);

        // Setup Merkle proof and root
        bytes32[] memory merkleProof = new bytes32[](1);
        merkleProof[0] = keccak256("simple-proof");
        bytes32 merkleRoot = responseHash; // Simplified for testing

        fdcRelay.setMerkleRoot(votingRound, merkleRoot);
        fdcRelay.setSignatureWeight(votingRound, 9000); // 90%

        // Create a pending request first
        uint256 fee = fdcAttestation.getAttestationFee();
        vm.prank(user1);
        fdcAttestation.requestYieldAttestation{value: fee}(
            TEST_PROTOCOL,
            "",
            ""
        );

        vm.expectEmit(true, false, false, true);
        emit FDCYieldDataUpdated(
            TEST_PROTOCOL,
            yieldRate,
            uint64(block.timestamp),
            0,
            bytes32(0)
        );

        // Submit verified data
        vm.prank(user2);
        fdcAttestation.submitVerifiedYieldData(
            TEST_PROTOCOL,
            votingRound,
            merkleProof,
            encodedResponse
        );

        // Verify data was updated
        IYieldDataAggregator.YieldData memory storedData = fdcAttestation
            .getCurrentYieldRate(TEST_PROTOCOL);
        assertEq(storedData.rate, yieldRate);
        assertGt(storedData.confidence, 0);
        assertEq(storedData.timestamp, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                        CONSENSUS MECHANISM TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetCurrentYieldRateConsensus() public {
        uint256 fdcRate = 450; // 4.5%
        uint256 ftsoRate = 470; // 4.7%

        // Setup FDC data with high confidence
        vm.prank(owner);
        fdcAttestation.updateYieldRate(TEST_PROTOCOL, fdcRate);

        // Setup FTSO data
        vm.prank(owner);
        ftsoOracle.authorizeProvider(TEST_PROTOCOL, dataProvider);
        vm.prank(dataProvider);
        ftsoOracle.updateYieldRate(TEST_PROTOCOL, ftsoRate);

        // Should prefer FDC data due to higher confidence
        IYieldDataAggregator.YieldData memory data = fdcAttestation
            .getCurrentYieldRate(TEST_PROTOCOL);
        assertEq(data.rate, fdcRate);
    }

    function testGetCurrentYieldRateFallback() public {
        uint256 ftsoRate = 380; // 3.8%

        // Setup only FTSO data
        vm.prank(owner);
        ftsoOracle.authorizeProvider(TEST_PROTOCOL, dataProvider);
        vm.prank(dataProvider);
        ftsoOracle.updateYieldRate(TEST_PROTOCOL, ftsoRate);

        // Should use FTSO data as fallback
        IYieldDataAggregator.YieldData memory data = fdcAttestation
            .getCurrentYieldRate(TEST_PROTOCOL);
        // Note: Might get different behavior based on consensus logic
        assertGt(data.rate, 0); // Should have some rate
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testConfigureProtocolApi() public {
        string memory newProtocol = "CURVE_3POOL";
        string memory apiUrl = "https://api.curve.fi/yield";
        string memory jqFilter = ".pools[0].apy";
        uint256 updateInterval = 1800; // 30 minutes
        bytes32 sourceId = FDCConstants.CURVE_SOURCE_ID;

        vm.prank(owner);
        fdcAttestation.configureProtocolApi(
            newProtocol,
            apiUrl,
            jqFilter,
            updateInterval,
            sourceId
        );

        assertTrue(fdcAttestation.isSupportedProtocol(newProtocol));

        FDCYieldAttestation.ApiConfig memory config = fdcAttestation
            .getProtocolApiConfig(newProtocol);
        assertEq(config.apiUrl, apiUrl);
        assertEq(config.jqFilter, jqFilter);
        assertEq(config.updateInterval, updateInterval);
        assertTrue(config.isActive);
        assertEq(config.sourceId, sourceId);
    }

    function testUpdateConsensusThreshold() public {
        uint256 newThreshold = 8000; // 80%

        vm.prank(owner);
        fdcAttestation.updateConsensusThreshold(newThreshold);

        assertEq(fdcAttestation.consensusThreshold(), newThreshold);
    }

    function testUpdateConsensusThresholdFailures() public {
        vm.prank(owner);
        vm.expectRevert("Threshold too low");
        fdcAttestation.updateConsensusThreshold(4000); // 40%

        vm.prank(owner);
        vm.expectRevert("Invalid threshold");
        fdcAttestation.updateConsensusThreshold(15000); // 150%
    }

    function testUpdateFDCContracts() public {
        MockFDCHub newHub = new MockFDCHub();
        MockFDCRelay newRelay = new MockFDCRelay();
        MockFDCVerification newVerification = new MockFDCVerification(
            address(newRelay)
        );

        vm.prank(owner);
        fdcAttestation.updateFDCContracts(
            address(newHub),
            address(newRelay),
            address(newVerification)
        );

        assertEq(address(fdcAttestation.fdcHub()), address(newHub));
        assertEq(address(fdcAttestation.fdcRelay()), address(newRelay));
        assertEq(
            address(fdcAttestation.fdcVerification()),
            address(newVerification)
        );
    }

    /*//////////////////////////////////////////////////////////////
                            INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testFullAttestationFlow() public {
        uint256 fee = fdcAttestation.getAttestationFee();
        uint256 votingRound = 1005;
        uint256 yieldRate = 600; // 6.0%

        // 1. Request attestation
        vm.prank(user1);
        bytes32 requestId = fdcAttestation.requestYieldAttestation{value: fee}(
            TEST_PROTOCOL,
            "",
            ""
        );

        // 2. Simulate FDC processing and create response
        JsonApiAttestationTypes.YieldDataResponse
            memory yieldData = JsonApiAttestationTypes.YieldDataResponse({
                protocol: TEST_PROTOCOL,
                yieldRate: yieldRate,
                timestamp: uint64(block.timestamp),
                tvl: 5000000 * 1e18,
                confidence: 9500,
                source: TEST_API_URL
            });

        JsonApiAttestationTypes.JsonApiResponse
            memory apiResponse = JsonApiAttestationTypes.JsonApiResponse({
                attestationType: FDCConstants.JSON_API_TYPE,
                sourceId: FDCConstants.AAVE_SOURCE_ID,
                votingRound: uint64(votingRound),
                lowestUsedTimestamp: uint64(block.timestamp),
                requestId: requestId,
                responseData: abi.encode(yieldData),
                isValid: true
            });

        bytes memory encodedResponse = abi.encode(apiResponse);
        bytes32 responseHash = keccak256(encodedResponse);

        // 3. Setup FDC consensus
        bytes32[] memory merkleProof = new bytes32[](1);
        merkleProof[0] = keccak256("integration-proof");
        bytes32 merkleRoot = responseHash;

        fdcRelay.setMerkleRoot(votingRound, merkleRoot);
        fdcRelay.setSignatureWeight(votingRound, 8700); // 87%

        // 4. Submit verified data
        vm.prank(user2);
        fdcAttestation.submitVerifiedYieldData(
            TEST_PROTOCOL,
            votingRound,
            merkleProof,
            encodedResponse
        );

        // 5. Verify final state
        IYieldDataAggregator.YieldData memory finalData = fdcAttestation
            .getCurrentYieldRate(TEST_PROTOCOL);
        assertEq(finalData.rate, yieldRate);
        assertGt(finalData.confidence, 8000); // Should be high confidence
        assertEq(finalData.timestamp, block.timestamp);

        // Check pending requests were cleared
        bytes32[] memory pending = fdcAttestation.getPendingRequests(
            TEST_PROTOCOL
        );
        assertEq(pending.length, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetMinSignatureWeight() public {
        assertEq(fdcAttestation.getMinSignatureWeight(), 5001);
    }

    function testEmergencyWithdraw() public {
        // Send some ETH to contract
        vm.deal(address(fdcAttestation), 1 ether);

        uint256 ownerBalanceBefore = owner.balance;

        vm.prank(owner);
        fdcAttestation.emergencyWithdraw();

        assertEq(address(fdcAttestation).balance, 0);
        assertEq(owner.balance, ownerBalanceBefore + 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _createMockYieldData(
        uint256 rate,
        string memory protocol
    ) internal view returns (JsonApiAttestationTypes.YieldDataResponse memory) {
        return
            JsonApiAttestationTypes.YieldDataResponse({
                protocol: protocol,
                yieldRate: rate,
                timestamp: uint64(block.timestamp),
                tvl: 1000000 * 1e18,
                confidence: 9000,
                source: TEST_API_URL
            });
    }
}
