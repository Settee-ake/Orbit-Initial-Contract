# Orbit Initial Contract

## Overview

Orbit is a decentralized exchange platform on the Hedera hashgraph. Its network of on-chain automated market makers (AMMs) supports instant token-to-token trades, as well as single-sided liquidity provision. With the solution of IL protection adapted from Bancor protocol, all liquidity providers will have upto 100% impermanent loss protections in all asset types listed.

## Features
- Single assets trading (no traditional LP paired tokens in any pools for trading, instead we use "Orbital Pool".)
- IL protection Mechanism
- Single-sided Liquidity Provision 
- No deposit limitation
- Sustainable Reward (fees)
- Rewarded Token = Deposited Token
- Auto-compounding yields
- Third Party IL Protection
- Composable Pool Tokens
- Flash Loans Service
- Tokenomics(Coming Soon)


## Security Warning

The repository is incompleted and is a part of the Orbit platform on the Hedera Hashgraph. Code testing and auditing will be committed. The upcoming version is expected to replace the current one without notice. Please make sure to understand the risks before using it.


## Setup

As a first step of contributing to the repo, you should install all the required dependencies via:

```sh
yarn install
```

You will also need to create and update the `.env` file if you’d like to interact or run the unit tests against mainnet forks (see [.env.example](./.env.example))


## Deployments

The contracts have built-in support for deployments on different chains and mainnet forks, powered by the awesome [hardhat-deploy](https://github.com/wighawag/hardhat-deploy) framework (tip of the hat to @wighawag for the crazy effort him and the rest of the contributors have put into the project).

```sh
yarn deploy
```


## Code Efficiency

The code was orginally written for the Ethereum blockchain and was committed for Hedera hashgraph. The team decide to fully operate the protocol on Hedera Hashgraph which means the next version and so on will be designed specifically for it. 

