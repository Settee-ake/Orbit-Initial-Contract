// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.13;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { ITokenGovernance } from "@bancor/token-governance/contracts/ITokenGovernance.sol";

import { Token } from "../token/Token.sol";

import { IVersioned } from "../utility/interfaces/IVersioned.sol";
import { Upgradeable } from "../utility/Upgradeable.sol";
import { Utils, InvalidStakedBalance } from "../utility/Utils.sol";
import { PPM_RESOLUTION } from "../utility/Constants.sol";
import { Fraction } from "../utility/FractionLibrary.sol";
import { MathExtend } from "../utility/MathExtend.sol";

import { INukleusNetwork } from "../network/interfaces/INukleusNetwork.sol";
import { INetworkSettings, NotWhitelisted } from "../network/interfaces/INetworkSettings.sol";

import { IMasterVault } from "../vaults/interfaces/IMasterVault.sol";

// prettier-ignore
import {
    INukleusPool,
    ROLE_NUKLEUS_POOL_TOKEN_MANAGER,
    ROLE_NUKLEUS_MANAGER,
    ROLE_VAULT_MANAGER,
    ROLE_FUNDING_MANAGER
} from "./interfaces/INukleusPool.sol";

import { IPoolToken } from "./interfaces/IPoolToken.sol";
import { IPoolCollection, Pool } from "./interfaces/IPoolCollection.sol";

import { Token } from "../token/Token.sol";
import { TokenLibrary } from "../token/TokenLibrary.sol";

import { Vault } from "../vaults/Vault.sol";
import { IVault } from "../vaults/interfaces/IVault.sol";

import { PoolToken } from "./PoolToken.sol";

/**
 * @dev Nukleus Pool contract
 */
contract NukleusPool is INukleusPool, Vault {
    using TokenLibrary for Token;

    error FundingLimitExceeded();

    struct InternalWithdrawalAmounts {
        uint256 nukleusAmount;
        uint256 withdrawalFeeAmount;
    }

    // the network contract
    INukleusNetwork private immutable _network;

    // the network settings contract
    INetworkSettings private immutable _networkSettings;

    // the master vault contract
    IMasterVault private immutable _masterVault;

    // the Nukleus pool token
    IPoolToken internal immutable _poolToken;

    // the total staked Nukleus balance in the network
    uint256 private _stakedBalance;

    // a mapping between pools and their current funding
    mapping(Token => uint256) private _currentPoolFunding;

    // upgrade forward-compatibility storage gap
    uint256[MAX_GAP - 2] private __gap;

    /**
     * @dev triggered when liquidity is deposited
     */
    event TokensDeposited(
        bytes32 indexed contextId,
        address indexed provider,
        uint256 nukleusAmount,
        uint256 poolTokenAmount,
        uint256 vnukleusAmount
    );

    /**
     * @dev triggered when liquidity is withdrawn
     */
    event TokensWithdrawn(
        bytes32 indexed contextId,
        address indexed provider,
        uint256 nukleusAmount,
        uint256 poolTokenAmount,
        uint256 vnukleusAmount,
        uint256 withdrawalFeeAmount
    );

    /**
     * @dev triggered when funding is requested
     */
    event FundingRequested(bytes32 indexed contextId, Token indexed pool, uint256 nukleusAmount, uint256 poolTokenAmount);

    /**
     * @dev triggered when funding is renounced
     */
    event FundingRenounced(bytes32 indexed contextId, Token indexed pool, uint256 nukleusAmount, uint256 poolTokenAmount);

    /**
     * @dev triggered when the total liquidity in the Nukleus pool is updated
     */
    event TotalLiquidityUpdated(
        bytes32 indexed contextId,
        uint256 liquidity,
        uint256 stakedBalance,
        uint256 poolTokenSupply
    );

    /**
     * @dev a "virtual" constructor that is only used to set immutable state variables
     */
    constructor(
        IBancorNetwork initNetwork,
        ITokenGovernance initNukleusGovernance,
        ITokenGovernance initVNukleusGovernance,
        INetworkSettings initNetworkSettings,
        IMasterVault initMasterVault,
        IPoolToken initNukleusPoolToken
    )
        Vault(initNukleusGovernance, initVNukleusGovernance)
        validAddress(address(initNetwork))
        validAddress(address(initNetworkSettings))
        validAddress(address(initMasterVault))
        validAddress(address(initNukleusPoolToken))
    {
        _network = initNetwork;
        _networkSettings = initNetworkSettings;
        _masterVault = initMasterVault;
        _poolToken = initNukleusPoolToken;
    }

    /**
     * @dev fully initializes the contract and its parents
     */
    function initialize() external initializer {
        __NukleusPool_init();
    }

    // solhint-disable func-name-mixedcase

    /**
     * @dev initializes the contract and its parents
     */
    function __NukleusPool_init() internal onlyInitializing {
        __Vault_init();

        __NukleusPool_init_unchained();
    }

    /**
     * @dev performs contract-specific initialization
     */
    function __NukleusPool_init_unchained() internal onlyInitializing {
        _poolToken.acceptOwnership();

        // set up administrative roles
        _setRoleAdmin(ROLE_NUKLEUS_POOL_TOKEN_MANAGER, ROLE_ADMIN);
        _setRoleAdmin(ROLE_NUKLEUS_MANAGER, ROLE_ADMIN);
        _setRoleAdmin(ROLE_VAULT_MANAGER, ROLE_ADMIN);
        _setRoleAdmin(ROLE_FUNDING_MANAGER, ROLE_ADMIN);
    }

    // solhint-enable func-name-mixedcase

    modifier poolWhitelisted(Token pool) {
        _poolWhitelisted(pool);

        _;
    }

    /**
     * @dev validates that the provided pool is whitelisted
     */
    function _poolWhitelisted(Token pool) internal view {
        if (!_networkSettings.isTokenWhitelisted(pool)) {
            revert NotWhitelisted();
        }
    }

    /**
     * @inheritdoc Upgradeable
     */
    function version() public pure override(IVersioned, Upgradeable) returns (uint16) {
        return 1;
    }

    /**
     * @inheritdoc Vault
     */
    function isPayable() public pure override(IVault, Vault) returns (bool) {
        return false;
    }

    /**
     * @dev returns the Nukleus pool token manager role
     */
    function roleNukleusPoolTokenManager() external pure returns (bytes32) {
        return ROLE_NUKLEUS_POOL_TOKEN_MANAGER;
    }

    /**
     * @dev returns the Nukleus manager role
     */
    function roleNukleusManager() external pure returns (bytes32) {
        return ROLE_NUKLEUS_MANAGER;
    }

    /**
     * @dev returns the vault manager role
     */
    function roleVaultManager() external pure returns (bytes32) {
        return ROLE_VAULT_MANAGER;
    }

    /**
     * @dev returns the funding manager role
     */
    function roleFundingManager() external pure returns (bytes32) {
        return ROLE_FUNDING_MANAGER;
    }

    /**
     * @dev returns whether the given caller is allowed access to the given token
     *
     * requirements:
     *
     * - the token must be the Nukleus pool token
     * - the caller must have the ROLE_NUKLEUS_POOL_TOKEN_MANAGER role
     */
    function isAuthorizedWithdrawal(
        address caller,
        Token token,
        address, /* target */
        uint256 /* amount */
    ) internal view override returns (bool) {
        return token.isEqual(_poolToken) && hasRole(ROLE_NUKLEUS_POOL_TOKEN_MANAGER, caller);
    }

    /**
     * @inheritdoc INukleusPool
     */
    function poolToken() external view returns (IPoolToken) {
        return _poolToken;
    }

    /**
     * @inheritdoc INukleusPool
     */
    function stakedBalance() external view returns (uint256) {
        return _stakedBalance;
    }

    /**
     * @inheritdoc INukleusPool
     */
    function currentPoolFunding(Token pool) external view returns (uint256) {
        return _currentPoolFunding[pool];
    }

    /**
     * @inheritdoc INukleusPool
     */
    function availableFunding(Token pool) external view returns (uint256) {
        return MathEx.subMax0(_networkSettings.poolFundingLimit(pool), _currentPoolFunding[pool]);
    }

    /**
     * @inheritdoc INukleusPool
     */
    function poolTokenToUnderlying(uint256 poolTokenAmount) external view returns (uint256) {
        return _poolTokenToUnderlying(poolTokenAmount);
    }

    /**
     * @inheritdoc INukleusPool
     */
    function underlyingToPoolToken(uint256 nukleusAmount) external view returns (uint256) {
        return _underlyingToPoolToken(nukleusAmount);
    }

    /**
     * @inheritdoc INukleusPool
     */
    function poolTokenAmountToBurn(uint256 nukleusAmountToDistribute) external view returns (uint256) {
        if (nukleusAmountToDistribute == 0) {
            return 0;
        }

        uint256 poolTokenSupply = _poolToken.totalSupply();
        uint256 val = nukleusAmountToDistribute * poolTokenSupply;

        return
            MathEx.mulDivF(
                val,
                poolTokenSupply,
                val + _stakedBalance * (poolTokenSupply - _poolToken.balanceOf(address(this)))
            );
    }

    /**
     * @inheritdoc INukleusPool
     */
    function mint(address recipient, uint256 nukleusAmount)
        external
        onlyRoleMember(ROLE_NUKLEUS_MANAGER)
        validAddress(recipient)
        greaterThanZero(nukleusAmount)
    {
        _nukleusGovernance.mint(recipient, nukleusAmount);
    }

    /**
     * @inheritdoc INukleusPool
     */
    function burnFromVault(uint256 nukleusAmount) external onlyRoleMember(ROLE_VAULT_MANAGER) greaterThanZero(nukleusAmount) {
        _masterVault.burn(Token(address(_nukleus)), nukleusAmount);
    }

    /**
     * @inheritdoc INukleusPool
     */
    function depositFor(
        bytes32 contextId,
        address provider,
        uint256 nukleusAmount,
        bool isMigrating,
        uint256 originalVnukleusAmount
    ) external only(address(_network)) validAddress(provider) greaterThanZero(nukleusAmount) returns (uint256) {
        // calculate the pool token amount to transfer
        uint256 poolTokenAmount = _underlyingToPoolToken(nukleusAmount);

        // transfer pool tokens from the protocol to the provider. Please note that it's not possible to deposit
        // liquidity requiring the protocol to transfer the provider more protocol tokens than it holds
        _poolToken.transfer(provider, poolTokenAmount);

        // burn the previously received Nukleus
        _nukleusGovernance.burn(nukleusAmount);

        uint256 vnukleusAmount = poolTokenAmount;

        // the provider should receive pool tokens and VNukleus in equal amounts. since the provider might already have
        // some VNukleus during migration, the contract only mints the delta between the full amount and the amount the
        // provider already has
        if (isMigrating) {
            vnukleusAmount = MathEx.subMax0(vnukleusAmount, originalVnukleusAmount);
        }

        // mint VNukleus to the provider
        if (vnukleusAmount > 0) {
            _vnukleusGovernance.mint(provider, vnukleusAmount);
        }

        emit TokensDeposited({
            contextId: contextId,
            provider: provider,
            nukleusAmount: nukleusAmount,
            poolTokenAmount: poolTokenAmount,
            vnukleusAmount: vnukleusAmount
        });

        return poolTokenAmount;
    }

    /**
     * @inheritdoc INukleusPool
     */
    function withdraw(
        bytes32 contextId,
        address provider,
        uint256 poolTokenAmount
    ) external only(address(_network)) validAddress(provider) greaterThanZero(poolTokenAmount) returns (uint256) {
        InternalWithdrawalAmounts memory amounts = _withdrawalAmounts(poolTokenAmount);

        // get the pool tokens from the caller
        _poolToken.transferFrom(msg.sender, address(this), poolTokenAmount);

        // burn the respective VNukleus amount
        _vnukleusGovernance.burn(poolTokenAmount);

        // mint Nukleus to the provider
        _nukleusGovernance.mint(provider, amounts.nukleusAmount);

        emit TokensWithdrawn({
            contextId: contextId,
            provider: provider,
            nukleusAmount: amounts.nukleusAmount,
            poolTokenAmount: poolTokenAmount,
            vnukleusAmount: poolTokenAmount,
            withdrawalFeeAmount: amounts.withdrawalFeeAmount
        });

        return amounts.nukleusAmount;
    }

    /**
     * @inheritdoc INukleusPool
     */
    function withdrawalAmount(uint256 poolTokenAmount)
        external
        view
        greaterThanZero(poolTokenAmount)
        returns (uint256)
    {
        InternalWithdrawalAmounts memory amounts = _withdrawalAmounts(poolTokenAmount);

        return amounts.nukleusAmount;
    }

    /**
     * @inheritdoc INukleusPool
     */
    function requestFunding(
        bytes32 contextId,
        Token pool,
        uint256 nukleusAmount
    ) external onlyRoleMember(ROLE_FUNDING_MANAGER) poolWhitelisted(pool) greaterThanZero(nukleusAmount) {
        uint256 currentFunding = _currentPoolFunding[pool];
        uint256 fundingLimit = _networkSettings.poolFundingLimit(pool);
        uint256 newFunding = currentFunding + nukleusAmount;

        // verify that the new funding amount doesn't exceed the limit
        if (newFunding > fundingLimit) {
            revert FundingLimitExceeded();
        }

        // calculate the pool token amount to mint
        uint256 currentStakedBalance = _stakedBalance;
        uint256 poolTokenAmount;
        uint256 poolTokenTotalSupply = _poolToken.totalSupply();
        if (poolTokenTotalSupply == 0) {
            // if this is the initial liquidity provision - use a one-to-one pool token to Nukleus rate
            if (currentStakedBalance > 0) {
                revert InvalidStakedBalance();
            }

            poolTokenAmount = nukleusAmount;
        } else {
            poolTokenAmount = _underlyingToPoolToken(nukleusAmount, poolTokenTotalSupply, currentStakedBalance);
        }

        // update the staked balance
        uint256 newStakedBalance = currentStakedBalance + nukleusAmount;
        _stakedBalance = newStakedBalance;

        // update the current funding amount
        _currentPoolFunding[pool] = newFunding;

        // mint pool tokens to the protocol
        _poolToken.mint(address(this), poolTokenAmount);

        // mint Nukleus to the vault
        _nukleusGovernance.mint(address(_masterVault), nukleusAmount);

        emit FundingRequested({
            contextId: contextId,
            pool: pool,
            nukleusAmount: nukleusAmount,
            poolTokenAmount: poolTokenAmount
        });

        emit TotalLiquidityUpdated({
            contextId: contextId,
            liquidity: _nukleus.balanceOf(address(_masterVault)),
            stakedBalance: newStakedBalance,
            poolTokenSupply: poolTokenTotalSupply + poolTokenAmount
        });
    }

    /**
     * @inheritdoc INukleusPool
     */
    function renounceFunding(
        bytes32 contextId,
        Token pool,
        uint256 nukleusAmount
    ) external onlyRoleMember(ROLE_FUNDING_MANAGER) poolWhitelisted(pool) greaterThanZero(nukleusAmount) {
        uint256 currentStakedBalance = _stakedBalance;

        // calculate the renounced amount to deduct from both the staked balance and current pool funding
        uint256 currentFunding = _currentPoolFunding[pool];
        uint256 reduceFundingAmount = Math.min(currentFunding, nukleusAmount);

        // calculate the pool token amount to burn
        uint256 poolTokenTotalSupply = _poolToken.totalSupply();
        uint256 poolTokenAmount = _underlyingToPoolToken(
            reduceFundingAmount,
            poolTokenTotalSupply,
            currentStakedBalance
        );

        // update the current pool funding. Note that the given amount can be higher than the funding amount but the
        // request shouldn't fail (and the funding amount cannot get negative)
        _currentPoolFunding[pool] = currentFunding - reduceFundingAmount;

        // update the staked balance
        uint256 newStakedBalance = currentStakedBalance - reduceFundingAmount;
        _stakedBalance = newStakedBalance;

        // burn pool tokens from the protocol
        _poolToken.burn(poolTokenAmount);

        // burn all Nukleus from the master vault
        _masterVault.burn(Token(address(_nukleus)), nukleusAmount);

        emit FundingRenounced({
            contextId: contextId,
            pool: pool,
            nukleusAmount: nukleusAmount,
            poolTokenAmount: poolTokenAmount
        });

        emit TotalLiquidityUpdated({
            contextId: contextId,
            liquidity: _nukleus.balanceOf(address(_masterVault)),
            stakedBalance: newStakedBalance,
            poolTokenSupply: poolTokenTotalSupply - poolTokenAmount
        });
    }

    /**
     * @inheritdoc INukleusPool
     */
    function onFeesCollected(
        Token pool,
        uint256 feeAmount,
        bool isTradeFee
    ) external only(address(_network)) validAddress(address(pool)) {
        if (feeAmount == 0) {
            return;
        }

        // increase the staked balance by the given amount
        _stakedBalance += feeAmount;

        if (isTradeFee) {
            // increase the current funding for the specified pool by the given amount
            _currentPoolFunding[pool] += feeAmount;
        }
    }

    /**
     * @dev converts the specified pool token amount to the underlying Nukleus amount
     */
    function _poolTokenToUnderlying(uint256 poolTokenAmount) private view returns (uint256) {
        return MathEx.mulDivF(poolTokenAmount, _stakedBalance, _poolToken.totalSupply());
    }

    /**
     * @dev converts the specified underlying Nukleus amount to pool token amount
     */
    function _underlyingToPoolToken(uint256 nukleusAmount) private view returns (uint256) {
        return _underlyingToPoolToken(nukleusAmount, _poolToken.totalSupply(), _stakedBalance);
    }

    /**
     * @dev converts the specified underlying Nukleus amount to pool token amount
     */
    function _underlyingToPoolToken(
        uint256 nukleusAmount,
        uint256 poolTokenTotalSupply,
        uint256 currentStakedBalance
    ) private pure returns (uint256) {
        return MathEx.mulDivC(nukleusAmount, poolTokenTotalSupply, currentStakedBalance);
    }

    /**
     * @dev returns withdrawal amounts
     */
    function _withdrawalAmounts(uint256 poolTokenAmount) internal view returns (InternalWithdrawalAmounts memory) {
        // calculate Nukleus amount to transfer
        uint256 nukleusAmount = _poolTokenToUnderlying(poolTokenAmount);

        // deduct the exit fee from Nukleus amount
        uint256 withdrawalFeeAmount = MathEx.mulDivF(nukleusAmount, _networkSettings.withdrawalFeePPM(), PPM_RESOLUTION);

        nukleusAmount -= withdrawalFeeAmount;

        return InternalWithdrawalAmounts({ nukleusAmount: nukleusAmount, withdrawalFeeAmount: withdrawalFeeAmount });
    }
}
