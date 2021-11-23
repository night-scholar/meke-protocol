# Meke Protocol

## Usage

### Pre Requisites

Before running any command, make sure to install dependencies:

```sh
$ yarn install
```

### Compile

Compile the smart contracts with Hardhat:

```sh
$ yarn compile
```

### Test

Run the Mocha tests:

```sh
$ yarn test
```

### setup deploy env

refer to `.env.example`

### Deploy contract to netowrk (requires Mnemonic and infura API key)

```
npx hardhat deploy --tags ArbTest --network ArbitrumTest
```

### Validate a contract with etherscan (requires API ke)

```
npx hardhat verify --network <network> <DEPLOYED_CONTRACT_ADDRESS> "Constructor argument 1"
```