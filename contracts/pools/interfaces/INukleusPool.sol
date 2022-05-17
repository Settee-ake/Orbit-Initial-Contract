// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.13;

import { IPoolToken } from "./IPoolToken.sol";

import { Token } from "../../token/Token.sol";

import { IVault } from "../../vaults/interfaces/IVault.sol";

// the Nukleus pool token manager role is required to access the Nukleus pool tokens
bytes32 constant ROLE_NUCLEUS_POOL_TOKEN_MANAGER = keccak256("ROLE_NUCLEUS_POOL_TOKEN_MANAGER");

// the Nukleus manager role is required to request the Nukleus pool to mint Nukleus
bytes32 constant ROLE_NUCLEUS_MANAGER = keccak256("ROLE_NUCLEUS_MANAGER");

// the vault manager role is required to request the Nukleus pool to burn Nukleus from the master vault
bytes32 constant ROLE_VAULT_MANAGER = keccak256("ROLE_VAULT_MANAGER");

// the funding manager role is required to request or renounce funding from the Nukleus pool
bytes32 constant ROLE_FUNDING_MANAGER = keccak256("ROLE_FUNDING_MANAGER");

/**
 * @dev Nukleus Pool interface
 */
interface INukleusPool is IVault {
    /**
     * @dev returns the Nukleus pool token contract
     */
    function poolToken() external view returns (IPoolToken);

    /**
     * @dev returns the total staked Nukleus balance in the network
     */
    function stakedBalance() external view returns (uint256);

    /**
     * @dev returns the current funding of given pool
     */
    function currentPoolFunding(Token pool) external view returns (uint256);

    /**
     * @dev returns the available Nukleus funding for a given pool
     */
    function availableFunding(Token pool) external view returns (uint256);

    /**
     * @dev converts the specified pool token amount to the underlying Nukleus amount
     */
    function poolTokenToUnderlying(uint256 poolTokenAmount) external view returns (uint256);

    /**
     * @dev converts the specified underlying Nukleus amount to pool token amount
     */
    function underlyingToPoolToken(uint256 nukleusAmount) external view returns (uint256);

    /**
     * @dev returns the number of pool token to burn in order to increase everyone's underlying value by the specified
     * amount
     */
    function poolTokenAmountToBurn(uint256 nukleusAmountToDistribute) external view returns (uint256);

    /**
     * @dev mints Nukleus to the recipient
     *
     * requirements:
     *
     * - the caller must have the ROLE_NUKLEUS_MANAGER role
     */
    function mint(address recipient, uint256 nukleusAmount) external;

    /**
     * @dev burns Nukleus from the vault
     *
     * requirements:
     *
     * - the caller must have the ROLE_VAULT_MANAGER role
     */
    function burnFromVault(uint256 nukleusAmount) external;

    /**
     * @dev deposits Nukleus liquidity on behalf of a specific provider and returns the respective pool token amount
     *
     * requirements:
     *
     * - the caller must be the network contract
     * - Nukleus tokens must have been already deposited into the contract
     */
    function depositFor(
        bytes32 contextId,
        address provider,
        uint256 nukleusAmount,
        bool isMigrating,
        uint256 originalVNukleusAmount
    ) external returns (uint256);

    /**
     * @dev withdraws Nukleus liquidity on behalf of a specific provider and returns the withdrawn Nukleus amount
     *
     * requirements:
     *
     * - the caller must be the network contract
     * - VNukleus token must have been already deposited into the contract
     */
    function withdraw(
        bytes32 contextId,
        address provider,
        uint256 poolTokenAmount
    ) external returns (uint256);

    /**
     * @dev returns the withdrawn Nukleus amount
     */
    function withdrawalAmount(uint256 poolTokenAmount) external view returns (uint256);

    /**
     * @dev requests Nukleus funding
     *
     * requirements:
     *
     * - the caller must have the ROLE_FUNDING_MANAGER role
     * - the token must have been whitelisted
     * - the request amount should be below the funding limit for a given pool
     * - the average rate of the pool must not deviate too much from its spot rate
     */
    function requestFunding(
        bytes32 contextId,
        Token pool,
        uint256 nukleusAmount
    ) external;

    /**
     * @dev renounces Nukleus funding
     *
     * requirements:
     *
     * - the caller must have the ROLE_FUNDING_MANAGER role
     * - the token must have been whitelisted
     * - the average rate of the pool must not deviate too much from its spot rate
     */
    function renounceFunding(
        bytes32 contextId,
        Token pool,
        uint256 nukleusAmount
    ) external;

    /**
     * @dev notifies the pool of accrued fees
     *
     * requirements:
     *
     * - the caller must be the network contract
     */
    function onFeesCollected(
        Token pool,
        uint256 feeAmount,
        bool isTradeFee
    ) external;
}
