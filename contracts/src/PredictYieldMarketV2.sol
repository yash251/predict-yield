// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IFAsset.sol";
import "./interfaces/ISecureRandom.sol";

/**
 * @title ISimpleYieldOracle
 * @notice Simple interface for yield data oracle
 */
interface ISimpleYieldOracle {
    function getYieldData(
        string calldata protocol
    )
        external
        view
        returns (uint256 yieldRate, uint256 timestamp, uint8 decimals);
}

/**
 * @title PredictYieldMarketV2
 * @notice Enhanced prediction market platform with multi-oracle support
 * @dev Integrates FAssets, FTSOv2, FDC, and SecureRandom for comprehensive yield prediction markets
 */
contract PredictYieldMarketV2 is Ownable, ReentrancyGuard, Pausable {
    using RandomnessLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct Market {
        uint256 id;
        string description;
        address creator;
        uint256 targetYield; // Target yield rate (basis points: 1000 = 10%)
        uint256 creationTime;
        uint256 bettingEndTime;
        uint256 settlementTime;
        uint256 totalYesStake;
        uint256 totalNoStake;
        uint256 platformFee; // Basis points (100 = 1%)
        MarketStatus status;
        uint256 finalYield; // Actual yield at settlement (basis points)
        address winner; // YES_TOKEN or NO_TOKEN
        bool useRandomDuration; // Whether to use secure random for market duration
        bytes32 randomRequestId; // Request ID for secure random duration
    }

    struct Bet {
        address bettor;
        uint256 marketId;
        address position; // YES_TOKEN or NO_TOKEN
        uint256 amount;
        uint256 timestamp;
        bool claimed;
    }

    struct OracleData {
        uint256 ftsoPrice;
        uint256 fdcPrice;
        uint256 timestamp;
        uint256 confidence; // 0-100, higher is better
        bool isValid;
    }

    struct MarketConfig {
        uint256 minBettingDuration; // Minimum betting period (seconds)
        uint256 maxBettingDuration; // Maximum betting period (seconds)
        uint256 settlementDelay; // Delay between betting end and settlement (seconds)
        uint256 minStakeAmount; // Minimum stake per bet
        uint256 maxStakeAmount; // Maximum stake per bet
        uint256 platformFeeRate; // Default platform fee (basis points)
        uint256 oracleConfidenceThreshold; // Minimum confidence for oracle data
    }

    /*//////////////////////////////////////////////////////////////
                                ENUMS
    //////////////////////////////////////////////////////////////*/

    enum MarketStatus {
        Active, // Betting is open
        Closed, // Betting closed, awaiting settlement
        Settled, // Market settled with results
        Cancelled // Market cancelled (refunds available)
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Contracts
    IFAsset public immutable fxrp;
    ISimpleYieldOracle public immutable ftsoOracle;
    ISecureRandom public immutable secureRandom;

    // Market data
    mapping(uint256 => Market) public markets;
    mapping(uint256 => mapping(address => Bet[])) public userBets;
    mapping(address => uint256[]) public userMarkets;

    // Oracle data tracking
    mapping(uint256 => OracleData) public marketOracleData;

    // Configuration
    MarketConfig public config;

    // Counters
    uint256 public nextMarketId = 1;
    uint256 public totalMarkets;
    uint256 public totalVolume;

    // Constants for position tokens
    address public constant YES_TOKEN = address(0x1);
    address public constant NO_TOKEN = address(0x2);

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event MarketCreated(
        uint256 indexed marketId,
        address indexed creator,
        string description,
        uint256 targetYield,
        uint256 bettingEndTime,
        uint256 settlementTime,
        bool useRandomDuration
    );

    event BetPlaced(
        uint256 indexed marketId,
        address indexed bettor,
        address indexed position,
        uint256 amount,
        uint256 totalStake
    );

    event MarketSettled(
        uint256 indexed marketId,
        uint256 finalYield,
        address winner,
        uint256 totalPayout,
        uint256 platformFees
    );

    event MarketCancelled(
        uint256 indexed marketId,
        string reason,
        uint256 totalRefunds
    );

    event BetClaimed(
        uint256 indexed marketId,
        address indexed bettor,
        uint256 payout
    );

    event OracleDataUpdated(
        uint256 indexed marketId,
        uint256 ftsoPrice,
        uint256 fdcPrice,
        uint256 confidence,
        uint256 timestamp
    );

    event ConfigUpdated(
        uint256 minBettingDuration,
        uint256 maxBettingDuration,
        uint256 settlementDelay,
        uint256 platformFeeRate
    );

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier validMarket(uint256 marketId) {
        require(marketId > 0 && marketId < nextMarketId, "Invalid market ID");
        _;
    }

    modifier marketExists(uint256 marketId) {
        require(markets[marketId].id != 0, "Market does not exist");
        _;
    }

    modifier marketActive(uint256 marketId) {
        require(
            markets[marketId].status == MarketStatus.Active,
            "Market not active"
        );
        require(
            block.timestamp < markets[marketId].bettingEndTime,
            "Betting period ended"
        );
        _;
    }

    modifier validPosition(address position) {
        require(
            position == YES_TOKEN || position == NO_TOKEN,
            "Invalid position"
        );
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _fxrp,
        address _ftsoOracle,
        address _secureRandom,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_fxrp != address(0), "Invalid FXRP address");
        require(_ftsoOracle != address(0), "Invalid FTSO oracle address");
        require(_secureRandom != address(0), "Invalid SecureRandom address");

        fxrp = IFAsset(_fxrp);
        ftsoOracle = ISimpleYieldOracle(_ftsoOracle);
        secureRandom = ISecureRandom(_secureRandom);

        // Initialize configuration
        config = MarketConfig({
            minBettingDuration: 30 minutes,
            maxBettingDuration: 7 days,
            settlementDelay: 1 hours,
            minStakeAmount: 1e18, // 1 FXRP
            maxStakeAmount: 1000e18, // 1000 FXRP
            platformFeeRate: 200, // 2%
            oracleConfidenceThreshold: 70 // 70% confidence minimum
        });
    }

    /*//////////////////////////////////////////////////////////////
                            MARKET CREATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create a new prediction market
     * @param description Market description
     * @param targetYield Target yield rate in basis points (1000 = 10%)
     * @param bettingDuration Duration for betting period in seconds
     * @param useRandomDuration Whether to use secure random for duration variation
     * @return marketId The created market ID
     */
    function createMarket(
        string calldata description,
        uint256 targetYield,
        uint256 bettingDuration,
        bool useRandomDuration
    ) external whenNotPaused nonReentrant returns (uint256 marketId) {
        require(bytes(description).length > 0, "Empty description");
        require(
            targetYield > 0 && targetYield <= 10000,
            "Invalid target yield"
        ); // Max 100%
        require(
            bettingDuration >= config.minBettingDuration &&
                bettingDuration <= config.maxBettingDuration,
            "Invalid betting duration"
        );

        marketId = nextMarketId++;

        uint256 actualBettingDuration = bettingDuration;
        bytes32 randomRequestId = bytes32(0);

        // Add random duration variation if requested
        if (useRandomDuration) {
            // Request randomness for market duration (5-15% variation)
            uint256 randomSeed = uint256(
                keccak256(
                    abi.encodePacked(
                        marketId,
                        block.timestamp,
                        msg.sender,
                        targetYield
                    )
                )
            );

            randomRequestId = secureRandom.requestRandomness{
                value: 0.001 ether
            }(randomSeed);

            // For now, use instant randomness as fallback
            uint256 instantRandom = secureRandom.getInstantRandomness(
                randomSeed
            );
            uint256 variation = instantRandom.randomInRange(95, 115); // 95-115% of original duration
            actualBettingDuration = (bettingDuration * variation) / 100;
        }

        uint256 bettingEndTime = block.timestamp + actualBettingDuration;
        uint256 settlementTime = bettingEndTime + config.settlementDelay;

        markets[marketId] = Market({
            id: marketId,
            description: description,
            creator: msg.sender,
            targetYield: targetYield,
            creationTime: block.timestamp,
            bettingEndTime: bettingEndTime,
            settlementTime: settlementTime,
            totalYesStake: 0,
            totalNoStake: 0,
            platformFee: config.platformFeeRate,
            status: MarketStatus.Active,
            finalYield: 0,
            winner: address(0),
            useRandomDuration: useRandomDuration,
            randomRequestId: randomRequestId
        });

        totalMarkets++;

        emit MarketCreated(
            marketId,
            msg.sender,
            description,
            targetYield,
            bettingEndTime,
            settlementTime,
            useRandomDuration
        );

        return marketId;
    }

    /*//////////////////////////////////////////////////////////////
                              BETTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Place a bet on a market
     * @param marketId Market to bet on
     * @param position YES_TOKEN or NO_TOKEN
     * @param amount Amount of FXRP to stake
     */
    function placeBet(
        uint256 marketId,
        address position,
        uint256 amount
    )
        external
        validMarket(marketId)
        marketExists(marketId)
        marketActive(marketId)
        validPosition(position)
        whenNotPaused
        nonReentrant
    {
        require(amount >= config.minStakeAmount, "Stake below minimum");
        require(amount <= config.maxStakeAmount, "Stake above maximum");

        Market storage market = markets[marketId];

        // Transfer FXRP from user
        require(
            fxrp.transferFrom(msg.sender, address(this), amount),
            "FXRP transfer failed"
        );

        // Update market totals
        if (position == YES_TOKEN) {
            market.totalYesStake += amount;
        } else {
            market.totalNoStake += amount;
        }

        // Record bet
        Bet memory newBet = Bet({
            bettor: msg.sender,
            marketId: marketId,
            position: position,
            amount: amount,
            timestamp: block.timestamp,
            claimed: false
        });

        userBets[marketId][msg.sender].push(newBet);

        // Track user's markets
        bool marketTracked = false;
        uint256[] storage userMarketList = userMarkets[msg.sender];
        for (uint256 i = 0; i < userMarketList.length; i++) {
            if (userMarketList[i] == marketId) {
                marketTracked = true;
                break;
            }
        }
        if (!marketTracked) {
            userMarkets[msg.sender].push(marketId);
        }

        totalVolume += amount;

        uint256 totalStake = market.totalYesStake + market.totalNoStake;

        emit BetPlaced(marketId, msg.sender, position, amount, totalStake);
    }

    /*//////////////////////////////////////////////////////////////
                         MARKET SETTLEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Settle a market using multi-oracle consensus
     * @param marketId Market to settle
     */
    function settleMarket(
        uint256 marketId
    ) external validMarket(marketId) marketExists(marketId) nonReentrant {
        Market storage market = markets[marketId];

        require(market.status == MarketStatus.Active, "Market not active");
        require(
            block.timestamp >= market.settlementTime,
            "Settlement time not reached"
        );

        // Get oracle data with consensus
        OracleData memory oracleData = _getOracleConsensus(marketId);

        if (
            !oracleData.isValid ||
            oracleData.confidence < config.oracleConfidenceThreshold
        ) {
            // Cancel market if oracle data is unreliable
            _cancelMarket(marketId, "Oracle data unreliable");
            return;
        }

        // Store oracle data
        marketOracleData[marketId] = oracleData;

        // Determine winner based on final yield vs target
        market.finalYield = oracleData.ftsoPrice; // Use consensus price as final yield
        market.status = MarketStatus.Settled;

        address winner;
        if (market.finalYield >= market.targetYield) {
            winner = YES_TOKEN; // Yield reached or exceeded target
        } else {
            winner = NO_TOKEN; // Yield did not reach target
        }
        market.winner = winner;

        // Calculate payouts
        uint256 totalStake = market.totalYesStake + market.totalNoStake;
        uint256 platformFees = (totalStake * market.platformFee) / 10000;
        uint256 totalPayout = totalStake - platformFees;

        emit MarketSettled(
            marketId,
            market.finalYield,
            winner,
            totalPayout,
            platformFees
        );
        emit OracleDataUpdated(
            marketId,
            oracleData.ftsoPrice,
            oracleData.fdcPrice,
            oracleData.confidence,
            oracleData.timestamp
        );
    }

    /**
     * @notice Get multi-oracle consensus data
     * @param marketId Market ID for context
     * @return oracleData Consensus oracle data
     */
    function _getOracleConsensus(
        uint256 marketId
    ) internal view returns (OracleData memory oracleData) {
        // Get FTSO data
        (
            uint256 ftsoPrice,
            uint256 ftsoTimestamp,
            uint8 ftsoDecimals
        ) = ftsoOracle.getYieldData("USDC");

        // Get FDC data (mock implementation)
        uint256 fdcPrice = ftsoPrice; // In real implementation, this would call FDC
        uint256 fdcTimestamp = block.timestamp;

        // Calculate confidence based on price agreement and data freshness
        uint256 priceDeviation = ftsoPrice > fdcPrice
            ? ((ftsoPrice - fdcPrice) * 10000) / ftsoPrice
            : ((fdcPrice - ftsoPrice) * 10000) / fdcPrice;

        uint256 priceConfidence = priceDeviation < 100
            ? 100 - priceDeviation
            : 0; // Within 1%

        uint256 timestampConfidence = 100;
        if (block.timestamp - ftsoTimestamp > 300) {
            // Older than 5 minutes
            timestampConfidence = 50;
        } else if (block.timestamp - ftsoTimestamp > 60) {
            // Older than 1 minute
            timestampConfidence = 80;
        }

        uint256 confidence = (priceConfidence + timestampConfidence) / 2;

        // Convert price to basis points for yield representation
        uint256 finalPrice = (ftsoPrice + fdcPrice) / 2;

        return
            OracleData({
                ftsoPrice: finalPrice,
                fdcPrice: fdcPrice,
                timestamp: block.timestamp,
                confidence: confidence,
                isValid: confidence >= 50 // Minimum 50% confidence
            });
    }

    /**
     * @notice Cancel a market and enable refunds
     * @param marketId Market to cancel
     * @param reason Cancellation reason
     */
    function _cancelMarket(uint256 marketId, string memory reason) internal {
        Market storage market = markets[marketId];
        market.status = MarketStatus.Cancelled;

        uint256 totalRefunds = market.totalYesStake + market.totalNoStake;

        emit MarketCancelled(marketId, reason, totalRefunds);
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM WINNINGS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Claim winnings from a settled market
     * @param marketId Market to claim from
     */
    function claimWinnings(
        uint256 marketId
    ) external validMarket(marketId) marketExists(marketId) nonReentrant {
        Market storage market = markets[marketId];
        require(
            market.status == MarketStatus.Settled ||
                market.status == MarketStatus.Cancelled,
            "Market not settled or cancelled"
        );

        Bet[] storage bets = userBets[marketId][msg.sender];
        require(bets.length > 0, "No bets found");

        uint256 totalPayout = 0;

        for (uint256 i = 0; i < bets.length; i++) {
            if (bets[i].claimed) continue;

            bets[i].claimed = true;

            if (market.status == MarketStatus.Cancelled) {
                // Refund full stake for cancelled markets
                totalPayout += bets[i].amount;
            } else if (bets[i].position == market.winner) {
                // Calculate proportional winnings for winning bets
                uint256 totalStake = market.totalYesStake + market.totalNoStake;
                uint256 platformFees = (totalStake * market.platformFee) /
                    10000;
                uint256 netPool = totalStake - platformFees;

                uint256 winningStake = (market.winner == YES_TOKEN)
                    ? market.totalYesStake
                    : market.totalNoStake;

                if (winningStake > 0) {
                    totalPayout += (bets[i].amount * netPool) / winningStake;
                }
            }
            // Losing bets get nothing
        }

        require(totalPayout > 0, "No payout available");

        // Transfer payout
        require(
            fxrp.transfer(msg.sender, totalPayout),
            "Payout transfer failed"
        );

        emit BetClaimed(marketId, msg.sender, totalPayout);
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get market details
     * @param marketId Market ID
     * @return market Market details
     */
    function getMarket(
        uint256 marketId
    ) external view validMarket(marketId) returns (Market memory market) {
        return markets[marketId];
    }

    /**
     * @notice Get user's bets for a market
     * @param marketId Market ID
     * @param user User address
     * @return bets Array of user's bets
     */
    function getUserBets(
        uint256 marketId,
        address user
    ) external view validMarket(marketId) returns (Bet[] memory bets) {
        return userBets[marketId][user];
    }

    /**
     * @notice Get user's active markets
     * @param user User address
     * @return marketIds Array of market IDs the user has bet on
     */
    function getUserMarkets(
        address user
    ) external view returns (uint256[] memory marketIds) {
        return userMarkets[user];
    }

    /**
     * @notice Get oracle data for a market
     * @param marketId Market ID
     * @return oracleData Oracle consensus data
     */
    function getMarketOracleData(
        uint256 marketId
    )
        external
        view
        validMarket(marketId)
        returns (OracleData memory oracleData)
    {
        return marketOracleData[marketId];
    }

    /**
     * @notice Calculate potential payout for a bet
     * @param marketId Market ID
     * @param position YES_TOKEN or NO_TOKEN
     * @param amount Bet amount
     * @return payout Potential payout amount
     */
    function calculatePayout(
        uint256 marketId,
        address position,
        uint256 amount
    )
        external
        view
        validMarket(marketId)
        validPosition(position)
        returns (uint256 payout)
    {
        Market memory market = markets[marketId];

        uint256 totalStake = market.totalYesStake +
            market.totalNoStake +
            amount;
        uint256 platformFees = (totalStake * market.platformFee) / 10000;
        uint256 netPool = totalStake - platformFees;

        uint256 positionStake = (position == YES_TOKEN)
            ? market.totalYesStake + amount
            : market.totalNoStake + amount;

        if (positionStake > 0) {
            payout = (amount * netPool) / positionStake;
        } else {
            payout = 0;
        }
    }

    /**
     * @notice Get market statistics
     * @return totalMarketsCount Total number of markets created
     * @return totalVolumeAmount Total volume traded
     * @return activeMarkets Number of currently active markets
     */
    function getMarketStats()
        external
        view
        returns (
            uint256 totalMarketsCount,
            uint256 totalVolumeAmount,
            uint256 activeMarkets
        )
    {
        totalMarketsCount = totalMarkets;
        totalVolumeAmount = totalVolume;

        // Count active markets
        uint256 active = 0;
        for (uint256 i = 1; i < nextMarketId; i++) {
            if (markets[i].status == MarketStatus.Active) {
                active++;
            }
        }
        activeMarkets = active;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update market configuration
     * @param newConfig New configuration parameters
     */
    function updateConfig(MarketConfig calldata newConfig) external onlyOwner {
        require(
            newConfig.minBettingDuration > 0,
            "Invalid min betting duration"
        );
        require(
            newConfig.maxBettingDuration > newConfig.minBettingDuration,
            "Invalid max betting duration"
        );
        require(newConfig.settlementDelay > 0, "Invalid settlement delay");
        require(newConfig.platformFeeRate <= 1000, "Platform fee too high"); // Max 10%
        require(
            newConfig.oracleConfidenceThreshold <= 100,
            "Invalid confidence threshold"
        );

        config = newConfig;

        emit ConfigUpdated(
            newConfig.minBettingDuration,
            newConfig.maxBettingDuration,
            newConfig.settlementDelay,
            newConfig.platformFeeRate
        );
    }

    /**
     * @notice Emergency pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Withdraw platform fees (emergency only)
     * @param amount Amount to withdraw
     * @param recipient Recipient address
     */
    function emergencyWithdraw(
        uint256 amount,
        address recipient
    ) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        require(fxrp.transfer(recipient, amount), "Withdrawal failed");
    }
}
