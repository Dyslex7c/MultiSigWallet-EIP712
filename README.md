# MultiSig Wallet with EIP-712

Smart contract wallet deployed on base sepolia: 0xf1Da1b87f3364a8037A92aD31449eD5D91331B8c

1. **Deploy:** Initialize the contract with an array of owner addresses and the number of required approvals.
2. **Fund:** Transfer ETH directly to the deployed contract address.
3. **Submit:** An owner submits a transaction by signing off-chain with EIP-712 and then sending it on-chain.
4. **Approve & Execute:** Other owners approve the transaction. Once the approval threshold is met, execute the transaction.

## Deploy and verify the contract

```
source .env
forge script script/DeployMultiSigWallet.s.sol --rpc-url base_sepolia --broadcast --verify
```

## Export ABI

```
forge inspect MultiSigWallet abi --json > abi.json
```