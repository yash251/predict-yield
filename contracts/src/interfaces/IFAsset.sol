// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IFAsset
 * @notice Simplified interface for FAssets (FXRP) integration
 * @dev This interface provides the basic functionality needed for prediction markets
 */
interface IFAsset is IERC20 {
    /**
     * @notice Mint FXRP by providing collateral
     * @param amount Amount of FXRP to mint
     * @param collateralAmount Amount of collateral to provide
     * @return success Whether the minting was successful
     */
    function mint(
        uint256 amount,
        uint256 collateralAmount
    ) external returns (bool success);

    /**
     * @notice Redeem FXRP for underlying XRP
     * @param amount Amount of FXRP to redeem
     * @return success Whether the redemption was successful
     */
    function redeem(uint256 amount) external returns (bool success);

    /**
     * @notice Get the current collateral ratio for minting
     * @return ratio Current collateral ratio (in basis points)
     */
    function getCollateralRatio() external view returns (uint256 ratio);

    /**
     * @notice Get the minimum minting amount
     * @return amount Minimum amount that can be minted
     */
    function getMinMintAmount() external view returns (uint256 amount);

    /**
     * @notice Check if minting is currently enabled
     * @return enabled Whether minting is enabled
     */
    function isMintingEnabled() external view returns (bool enabled);
}

/**
 * @title IAssetManager
 * @notice Interface for FAssets Asset Manager contract
 * @dev Provides advanced FAssets functionality
 */
interface IAssetManager {
    /**
     * @notice Get the FAsset token contract
     * @return fAsset The FAsset token contract
     */
    function fAsset() external view returns (IERC20 fAsset);

    /**
     * @notice Get collateral token for an agent vault
     * @param agentVault Agent vault address
     * @return token Collateral token contract
     */
    function getAgentVaultCollateralToken(
        address agentVault
    ) external view returns (IERC20 token);

    /**
     * @notice Liquidate an agent vault
     * @param agentVault Agent vault to liquidate
     * @param maxFAssetAmount Maximum FAsset amount to use for liquidation
     * @return liquidatedFAsset Amount of FAsset used
     * @return obtainedVault Amount of vault collateral obtained
     * @return obtainedNative Amount of native collateral obtained
     */
    function liquidate(
        address agentVault,
        uint256 maxFAssetAmount
    )
        external
        returns (
            uint256 liquidatedFAsset,
            uint256 obtainedVault,
            uint256 obtainedNative
        );
}
 