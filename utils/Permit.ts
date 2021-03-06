import Contracts, { IERC20 } from '../components/Contracts';
import { MAX_UINT256, ZERO_ADDRESS } from './Constants';
import { NATIVE_TOKEN_ADDRESS } from './TokenData';
import { Addressable } from './Types';
import { signTypedData, SignTypedDataVersion, TypedDataUtils } from '@metamask/eth-sig-util';
import { fromRpcSig } from 'ethereumjs-util';
import { BigNumber, BigNumberish, utils, Wallet } from 'ethers';

const { formatBytes32String } = utils;

const VERSION = '1';
const HARDHAT_CHAIN_ID = 31337;
const PERMIT_TYPE: 'EIP712Domain' | 'Permit' = 'Permit';

const EIP712_DOMAIN = [
    { name: 'name', type: 'string' },
    { name: 'version', type: 'string' },
    { name: 'chainId', type: 'uint256' },
    { name: 'verifyingContract', type: 'address' }
];

const PERMIT = [
    { name: 'owner', type: 'address' },
    { name: 'spender', type: 'address' },
    { name: 'value', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' }
];

export const domainSeparator = (name: string, verifyingContract: string) => {
    return (
        '0x' +
        TypedDataUtils.hashStruct(
            'EIP712Domain',
            { name, version: VERSION, chainId: HARDHAT_CHAIN_ID, verifyingContract },
            { EIP712Domain: EIP712_DOMAIN },
            SignTypedDataVersion.V4
        ).toString('hex')
    );
};

export const permitData = (
    name: string,
    verifyingContract: string,
    owner: string,
    spender: string,
    amount: BigNumber,
    nonce: number,
    deadline: BigNumberish = MAX_UINT256
) => ({
    primaryType: PERMIT_TYPE,
    types: { EIP712Domain: EIP712_DOMAIN, Permit: PERMIT },
    domain: { name, version: VERSION, chainId: HARDHAT_CHAIN_ID, verifyingContract },
    message: { owner, spender, value: amount.toString(), nonce: nonce.toString(), deadline: deadline.toString() }
});

export const permitCustomSignature = async (
    wallet: Wallet,
    name: string,
    verifyingContract: string,
    spender: string,
    amount: BigNumber,
    nonce: number,
    deadline: BigNumberish
) => {
    const data = permitData(name, verifyingContract, await wallet.getAddress(), spender, amount, nonce, deadline);
    const signature = signTypedData({
        privateKey: Buffer.from(wallet.privateKey.slice(2), 'hex'),
        data,
        version: SignTypedDataVersion.V4
    });
    return fromRpcSig(signature);
};

export const permitSignature = async (
    owner: Wallet,
    tokenAddress: string,
    spender: Addressable,
    bnt: undefined | IERC20,
    amount: BigNumberish,
    deadline: BigNumberish
) => {
    if (
        tokenAddress === NATIVE_TOKEN_ADDRESS ||
        tokenAddress === ZERO_ADDRESS ||
        (bnt && tokenAddress === bnt.address)
    ) {
        return {
            v: 0,
            r: formatBytes32String(''),
            s: formatBytes32String('')
        };
    }

    const reserveToken = await Contracts.TestERC20Token.attach(tokenAddress);
    const ownerAddress = await owner.getAddress();

    const nonce = await reserveToken.nonces(ownerAddress);

    return permitCustomSignature(
        owner,
        await reserveToken.name(),
        reserveToken.address,
        spender.address,
        BigNumber.from(amount),
        nonce.toNumber(),
        BigNumber.from(deadline)
    );
};
