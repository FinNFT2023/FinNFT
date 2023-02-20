### Lockup amount calculation formula
#### The current user nft has not expired
// if cur <= start + rd; k = start - 1; else k = cur - rd -1
// a = sum_r[cur - 1] - sum_r[k];   // if k=0, sum_r[k] = 0
// b = sum_nr[cur - 1] - sum_nr[k]; // if k=0, sum_nr[k] = 0
// lock_amount = b - (cur - rd - 1) * a;

#### The current user NFT has expired
// if cur <= start + rd, k = start - 1, else k = cur - rd - 1
// a = sum_r[deadline - 1] - sum_r[k];
// b = sum_nr[deadline - 1] - sum_nr[k];
// lock_amount = b - (cur - rd - 1) * a;

### deploy proxy contract 
```shell
forge script script/Proxy.s.sol:ProxyScript --broadcast --verify --private-key $privateKey --rpc-url http://127.0.0.1:8545
```

### gen go abi file
```shell
mkdir -p gen
forge inspect FilNft abi|/usr/local/bin/abigen --abi - --pkg gen --type FilNft --out gen/filnft.go
```

