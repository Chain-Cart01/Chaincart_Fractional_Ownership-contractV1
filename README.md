# Fractional Ownership Protocol

A decentralized protocol for fractional ownership of assets using Ethereum and Chainlink price feeds.

## Overview

This project enables users to pool ETH contributions and receive fractional ownership tokens based on USD value. Each token represents $1 USD of contributed value, powered by Chainlink's decentralized price oracles.

## Features

- **USD-Based Token Minting**: 1 Token = $1 USD contributed
- **Chainlink Price Feeds**: Real-time ETH/USD conversion
- **ERC-20 Tokens**: Standard fractional ownership shares
- **Multi-Chain Support**: Deploys to Mainnet, Sepolia, and local networks

## Contracts

- `FractionalOwnership.sol`: Main contract handling contributions and token minting
- `FractionalOwnershipToken.sol`: ERC-20 token representing ownership shares

## Development

### Setup
```bash
forge install
forge build