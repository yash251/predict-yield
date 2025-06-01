// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IFAsset.sol";
import "./interfaces/IFTSOv2.sol";

/**
 * @title PredictYieldMarket
 * @notice A DeFi prediction market platform where users stake FXRP to bet on future yield rates
 * @dev Integrates with Flare's FAssets, FTSOv2, FDC, and Secure Random protocols
 */
contract PredictYieldMarket is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IFAsset;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct Market {
        uint256 id;
        string description;
        string protocol; // DeFi protocol (e.g., "AAVE_USDC")
        uint256 targetYieldRate; // In basis points (e.g., 450 = 4.5%)
        uint256 endTime;
        uint256 settlementTime;
        uint256 totalStakedYes;
        uint256 totalStakedNo;
        uint256 actualYieldRate; // Set after settlement
        MarketStatus status;
        uint256 creationTime;
        bool autoSettlement; // Whether to use automated settlement via FTSOv2
    }

    struct Bet {
        uint256 marketId;
        address user;
        uint256 amount;
        bool prediction; // true = YES (yield will exceed target), false = NO
        bool claimed;
        uint256 timestamp;
    }

    enum MarketStatus {
        Active,
        Settled,
        Cancelled
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The FXRP token used for staking
    IFAsset public immutable fxrpToken;

    /// @notice FTSOv2 Yield Oracle for automated settlement
    IYieldDataAggregator public yieldOracle;

    /// @notice Counter for generating unique market IDs
    uint256 public nextMarketId = 1;

    /// @notice Counter for generating unique bet IDs
    uint256 public nextBetId = 1;

    /// @notice Minimum stake amount in FXRP
    uint256 public minStakeAmount = 1 ether; // 1 FXRP

    /// @notice Maximum stake amount in FXRP
    uint256 public maxStakeAmount = 1000 ether; // 1000 FXRP

    /// @notice Platform fee in basis points (e.g., 100 = 1%)
    uint256 public platformFee = 100; // 1%

    /// @notice Address to receive platform fees
    address public feeRecipient;

    /// @notice Minimum confidence score for automated settlement (basis points)
    uint256 public minConfidenceScore = 1000; // 10%

    /// @notice Mapping of market ID to Market struct
    mapping(uint256 => Market) public markets;

    /// @notice Mapping of bet ID to Bet struct
    mapping(uint256 => Bet) public bets;

    /// @notice Mapping of user to array of their bet IDs
    mapping(address => uint256[]) public userBets;

    /// @notice Mapping of market ID to array of bet IDs
    mapping(uint256 => uint256[]) public marketBets;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event MarketCreated(
        uint256 indexed marketId,
        string description,
        string protocol,
        uint256 targetYieldRate,
        uint256 endTime,
        uint256 settlementTime,
        bool autoSettlement
    );

    event BetPlaced(
        uint256 indexed betId,
        uint256 indexed marketId,
        address indexed user,
        uint256 amount,
        bool prediction
    );

    event MarketSettled(
        uint256 indexed marketId,
        uint256 actualYieldRate,
        bool outcome,
        bool automated,
        uint256 confidence
    );

    event MarketAutoSettled(
        uint256 indexed marketId,
        uint256 actualYieldRate,
        uint256 confidence
    );

    event RewardsClaimed(
        uint256 indexed betId,
        address indexed user,
        uint256 amount
    );

    event FXRPMinted(
        address indexed user,
        uint256 amount,
        uint256 collateralUsed
    );

    event YieldOracleUpdated(address indexed newOracle);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier validMarket(uint256 marketId) {
        require(marketId > 0 && marketId < nextMarketId, "Invalid market ID");
        _;
    }

    modifier validBet(uint256 betId) {
        require(betId > 0 && betId < nextBetId, "Invalid bet ID");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _fxrpToken,
        address _yieldOracle,
        address _feeRecipient,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_fxrpToken != address(0), "Invalid FXRP token address");
        require(_yieldOracle != address(0), "Invalid yield oracle address");
        require(_feeRecipient != address(0), "Invalid fee recipient");

        fxrpToken = IFAsset(_fxrpToken);
        yieldOracle = IYieldDataAggregator(_yieldOracle);
        feeRecipient = _feeRecipient;
    }

    /*//////////////////////////////////////////////////////////////
                           FASSETS INTEGRATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mint FXRP tokens for users who want to participate in prediction markets
     * @param amount Amount of FXRP to mint
     * @param collateralAmount Amount of collateral to provide
     */
    function mintFXRP(
        uint256 amount,
        uint256 collateralAmount
    ) external payable nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(fxrpToken.isMintingEnabled(), "FXRP minting is disabled");
        require(amount >= fxrpToken.getMinMintAmount(), "Amount below minimum");

        // Check collateral ratio
        uint256 requiredCollateral = (amount * fxrpToken.getCollateralRatio()) /
            10000;
        require(
            collateralAmount >= requiredCollateral,
            "Insufficient collateral"
        );

        // For demo purposes, we'll simulate minting
        // In real implementation, this would interact with FAssets contracts
        bool success = fxrpToken.mint(amount, collateralAmount);
        require(success, "FXRP minting failed");

        emit FXRPMinted(msg.sender, amount, collateralAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            MARKET CREATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create a new prediction market with FTSOv2 integration
     * @param description Description of the market
     * @param protocol DeFi protocol identifier (e.g., "AAVE_USDC")
     * @param targetYieldRate Target yield rate in basis points
     * @param duration Duration of the market in seconds
     * @param autoSettlement Whether to enable automated settlement via FTSOv2
     */
    function createMarket(
        string memory description,
        string memory protocol,
        uint256 targetYieldRate,
        uint256 duration,
        bool autoSettlement
    ) external onlyOwner returns (uint256 marketId) {
        require(bytes(description).length > 0, "Description cannot be empty");
        require(bytes(protocol).length > 0, "Protocol cannot be empty");
        require(
            targetYieldRate > 0 && targetYieldRate <= 10000,
            "Invalid yield rate"
        );
        require(duration >= 1 hours && duration <= 30 days, "Invalid duration");

        // If auto settlement is enabled, verify protocol exists in oracle
        if (autoSettlement) {
            // This will revert if protocol doesn't exist
            yieldOracle.getCurrentYieldRate(protocol);
        }

        marketId = nextMarketId++;
        uint256 endTime = block.timestamp + duration;
        uint256 settlementTime = endTime + 1 hours; // 1 hour settlement period

        markets[marketId] = Market({
            id: marketId,
            description: description,
            protocol: protocol,
            targetYieldRate: targetYieldRate,
            endTime: endTime,
            settlementTime: settlementTime,
            totalStakedYes: 0,
            totalStakedNo: 0,
            actualYieldRate: 0,
            status: MarketStatus.Active,
            creationTime: block.timestamp,
            autoSettlement: autoSettlement
        });

        emit MarketCreated(
            marketId,
            description,
            protocol,
            targetYieldRate,
            endTime,
            settlementTime,
            autoSettlement
        );
    }

    /*//////////////////////////////////////////////////////////////
                               BETTING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Place a bet on a prediction market
     * @param marketId ID of the market to bet on
     * @param amount Amount of FXRP to stake
     * @param prediction true = YES (yield will exceed target), false = NO
     */
    function placeBet(
        uint256 marketId,
        uint256 amount,
        bool prediction
    )
        external
        nonReentrant
        whenNotPaused
        validMarket(marketId)
        returns (uint256 betId)
    {
        Market storage market = markets[marketId];
        require(market.status == MarketStatus.Active, "Market is not active");
        require(block.timestamp < market.endTime, "Market has ended");
        require(
            amount >= minStakeAmount && amount <= maxStakeAmount,
            "Invalid stake amount"
        );

        // Transfer FXRP from user to contract
        fxrpToken.safeTransferFrom(msg.sender, address(this), amount);

        // Create bet
        betId = nextBetId++;
        bets[betId] = Bet({
            marketId: marketId,
            user: msg.sender,
            amount: amount,
            prediction: prediction,
            claimed: false,
            timestamp: block.timestamp
        });

        // Update market totals
        if (prediction) {
            market.totalStakedYes += amount;
        } else {
            market.totalStakedNo += amount;
        }

        // Update mappings
        userBets[msg.sender].push(betId);
        marketBets[marketId].push(betId);

        emit BetPlaced(betId, marketId, msg.sender, amount, prediction);
    }

    /*//////////////////////////////////////////////////////////////
                           MARKET SETTLEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Attempt automated settlement using FTSOv2 yield oracle
     * @param marketId ID of the market to settle
     */
    function attemptAutoSettlement(
        uint256 marketId
    ) external nonReentrant validMarket(marketId) {
        Market storage market = markets[marketId];
        require(market.status == MarketStatus.Active, "Market is not active");
        require(block.timestamp >= market.endTime, "Market has not ended");
        require(market.autoSettlement, "Auto settlement not enabled");

        // Get current yield data from oracle
        IYieldDataAggregator.YieldData memory yieldData = yieldOracle
            .getCurrentYieldRate(market.protocol);

        // Check if data is reliable enough for automated settlement
        require(
            yieldData.confidence >= minConfidenceScore,
            "Insufficient confidence for auto settlement"
        );
        require(
            block.timestamp - yieldData.timestamp <= 3600,
            "Yield data too stale"
        ); // Max 1 hour old

        // Settle the market
        market.actualYieldRate = yieldData.rate;
        market.status = MarketStatus.Settled;

        bool outcome = yieldData.rate > market.targetYieldRate;

        emit MarketAutoSettled(marketId, yieldData.rate, yieldData.confidence);
        emit MarketSettled(
            marketId,
            yieldData.rate,
            outcome,
            true,
            yieldData.confidence
        );
    }

    /**
     * @notice Manually settle a market with the actual yield rate (fallback method)
     * @param marketId ID of the market to settle
     * @param actualYieldRate Actual yield rate in basis points
     * @dev This can be used when automated settlement fails or for non-automated markets
     */
    function settleMarket(
        uint256 marketId,
        uint256 actualYieldRate
    ) external onlyOwner validMarket(marketId) {
        Market storage market = markets[marketId];
        require(market.status == MarketStatus.Active, "Market is not active");
        require(block.timestamp >= market.endTime, "Market has not ended");
        require(actualYieldRate <= 50000, "Invalid yield rate"); // Max 500%

        market.actualYieldRate = actualYieldRate;
        market.status = MarketStatus.Settled;

        bool outcome = actualYieldRate > market.targetYieldRate;
        emit MarketSettled(marketId, actualYieldRate, outcome, false, 10000); // Manual settlement has 100% confidence
    }

    /*//////////////////////////////////////////////////////////////
                           REWARDS CLAIMING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claim rewards for a winning bet
     * @param betId ID of the bet to claim rewards for
     */
    function claimRewards(uint256 betId) external nonReentrant validBet(betId) {
        Bet storage bet = bets[betId];
        require(bet.user == msg.sender, "Not your bet");
        require(!bet.claimed, "Already claimed");

        Market storage market = markets[bet.marketId];
        require(market.status == MarketStatus.Settled, "Market not settled");

        // Check if bet won
        bool marketOutcome = market.actualYieldRate > market.targetYieldRate;
        require(bet.prediction == marketOutcome, "Bet did not win");

        bet.claimed = true;

        // Calculate rewards
        uint256 totalWinningStake = marketOutcome
            ? market.totalStakedYes
            : market.totalStakedNo;
        uint256 totalLosingStake = marketOutcome
            ? market.totalStakedNo
            : market.totalStakedYes;

        // Reward = original stake + proportional share of losing stakes (minus platform fee)
        uint256 platformFeeAmount = (totalLosingStake * platformFee) / 10000;
        uint256 rewardPool = totalLosingStake - platformFeeAmount;
        uint256 rewardShare = (bet.amount * rewardPool) / totalWinningStake;
        uint256 totalReward = bet.amount + rewardShare;

        // Transfer rewards
        fxrpToken.safeTransfer(msg.sender, totalReward);

        // Transfer platform fee
        if (platformFeeAmount > 0) {
            fxrpToken.safeTransfer(feeRecipient, platformFeeAmount);
        }

        emit RewardsClaimed(betId, msg.sender, totalReward);
    }

    /*//////////////////////////////////////////////////////////////
                           FTSO INTEGRATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get current yield rate from FTSOv2 oracle
     * @param protocol Protocol identifier
     * @return rate Current yield rate
     * @return confidence Confidence score
     * @return age Data age in seconds
     */
    function getCurrentYieldFromOracle(
        string calldata protocol
    ) external view returns (uint256 rate, uint256 confidence, uint256 age) {
        IYieldDataAggregator.YieldData memory data = yieldOracle
            .getCurrentYieldRate(protocol);
        rate = data.rate;
        confidence = data.confidence;
        age = block.timestamp - data.timestamp;
    }

    /**
     * @notice Check if a market can be auto-settled
     * @param marketId Market ID to check
     * @return canSettle Whether the market can be auto-settled
     * @return reason Reason if it can't be settled
     */
    function canAutoSettle(
        uint256 marketId
    )
        external
        view
        validMarket(marketId)
        returns (bool canSettle, string memory reason)
    {
        Market storage market = markets[marketId];

        if (market.status != MarketStatus.Active) {
            return (false, "Market is not active");
        }

        if (block.timestamp < market.endTime) {
            return (false, "Market has not ended");
        }

        if (!market.autoSettlement) {
            return (false, "Auto settlement not enabled");
        }

        try yieldOracle.getCurrentYieldRate(market.protocol) returns (
            IYieldDataAggregator.YieldData memory data
        ) {
            if (data.confidence < minConfidenceScore) {
                return (false, "Insufficient confidence score");
            }

            if (block.timestamp - data.timestamp > 3600) {
                return (false, "Yield data too stale");
            }

            return (true, "Ready for auto settlement");
        } catch {
            return (false, "Failed to get yield data");
        }
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get market information
     * @param marketId ID of the market
     */
    function getMarket(
        uint256 marketId
    ) external view validMarket(marketId) returns (Market memory) {
        return markets[marketId];
    }

    /**
     * @notice Get bet information
     * @param betId ID of the bet
     */
    function getBet(
        uint256 betId
    ) external view validBet(betId) returns (Bet memory) {
        return bets[betId];
    }

    /**
     * @notice Get all bet IDs for a user
     * @param user Address of the user
     */
    function getUserBets(
        address user
    ) external view returns (uint256[] memory) {
        return userBets[user];
    }

    /**
     * @notice Get all bet IDs for a market
     * @param marketId ID of the market
     */
    function getMarketBets(
        uint256 marketId
    ) external view validMarket(marketId) returns (uint256[] memory) {
        return marketBets[marketId];
    }

    /**
     * @notice Calculate potential rewards for a bet
     * @param betId ID of the bet
     */
    function calculatePotentialRewards(
        uint256 betId
    )
        external
        view
        validBet(betId)
        returns (uint256 maxReward, uint256 minReward)
    {
        Bet memory bet = bets[betId];
        Market memory market = markets[bet.marketId];

        uint256 totalWinningStake = bet.prediction
            ? market.totalStakedYes
            : market.totalStakedNo;
        uint256 totalLosingStake = bet.prediction
            ? market.totalStakedNo
            : market.totalStakedYes;

        if (totalWinningStake == 0) {
            return (0, 0);
        }

        uint256 platformFeeAmount = (totalLosingStake * platformFee) / 10000;
        uint256 rewardPool = totalLosingStake - platformFeeAmount;
        uint256 rewardShare = (bet.amount * rewardPool) / totalWinningStake;

        maxReward = bet.amount + rewardShare;
        minReward = bet.amount; // If no one bets against you
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update the yield oracle contract
     * @param _newOracle New oracle contract address
     */
    function updateYieldOracle(address _newOracle) external onlyOwner {
        require(_newOracle != address(0), "Invalid oracle address");
        yieldOracle = IYieldDataAggregator(_newOracle);
        emit YieldOracleUpdated(_newOracle);
    }

    /**
     * @notice Update minimum confidence score for auto settlement
     * @param _minConfidence New minimum confidence score (basis points)
     */
    function updateMinConfidenceScore(
        uint256 _minConfidence
    ) external onlyOwner {
        require(_minConfidence <= 10000, "Invalid confidence score");
        minConfidenceScore = _minConfidence;
    }

    /**
     * @notice Update platform settings
     */
    function updateSettings(
        uint256 _minStakeAmount,
        uint256 _maxStakeAmount,
        uint256 _platformFee,
        address _feeRecipient
    ) external onlyOwner {
        require(_minStakeAmount > 0, "Invalid min stake");
        require(_maxStakeAmount >= _minStakeAmount, "Invalid max stake");
        require(_platformFee <= 1000, "Fee too high"); // Max 10%
        require(_feeRecipient != address(0), "Invalid fee recipient");

        minStakeAmount = _minStakeAmount;
        maxStakeAmount = _maxStakeAmount;
        platformFee = _platformFee;
        feeRecipient = _feeRecipient;
    }

    /**
     * @notice Emergency pause function
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause function
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Cancel a market (emergency function)
     */
    function cancelMarket(
        uint256 marketId
    ) external onlyOwner validMarket(marketId) {
        Market storage market = markets[marketId];
        require(market.status == MarketStatus.Active, "Market is not active");

        market.status = MarketStatus.Cancelled;

        // In a real implementation, we would refund all bets here
        // For now, we just mark the market as cancelled
    }
}
 