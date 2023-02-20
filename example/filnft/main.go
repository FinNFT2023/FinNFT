package main

import (
	"context"
	"fmt"
	"log"
	"math/big"
	"os"

	"filnft/gen"

	"github.com/ethereum/go-ethereum/accounts"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"golang.org/x/crypto/sha3"
)

func hashText(msg []byte) [32]byte {
	hasher := sha3.NewLegacyKeccak256()
	hasher.Write(msg)
	return bytesTo32(hasher.Sum(nil))

}

func bytesTo32(b []byte) [32]byte {
	var ret [32]byte
	copy(ret[:], b[:32])
	return ret
}

func main() {
	cFilNftContract := os.Getenv("npm_package_config_filnft_contract")
	cEncoderPriKey := os.Getenv("npm_package_config_prikey_encoder")
	cOwnerPriKey := os.Getenv("npm_package_config_prikey_owner")
	client, err := ethclient.Dial("https://eth-goerli.g.alchemy.com/v2/Kfks3shTyNrzc33ZSIiT8dNA4TDPuTX6")
	// client, err := ethclient.Dial("http://127.0.0.1:8545")
	if err != nil {
		log.Fatal(err)
	}

	encoderPriKey, err := crypto.HexToECDSA(cEncoderPriKey)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("encode addr: %v \n", crypto.PubkeyToAddress(encoderPriKey.PublicKey))
	ownerPriKey, err := crypto.HexToECDSA(cOwnerPriKey)
	if err != nil {
		log.Fatal(err)
	}
	fromAddress := crypto.PubkeyToAddress(ownerPriKey.PublicKey)
	fmt.Printf("owner addr: %v \n", fromAddress)
	nonce, err := client.PendingNonceAt(context.Background(), fromAddress)
	if err != nil {
		log.Fatal(err)
	}

	gasPrice, err := client.SuggestGasPrice(context.Background())
	if err != nil {
		log.Fatal(err)
	}

	auth, err := bind.NewKeyedTransactorWithChainID(ownerPriKey, big.NewInt(5))
	if err != nil {
		log.Fatal(err)
	}
	auth.Nonce = big.NewInt(int64(nonce))
	auth.Value = big.NewInt(0)     // in wei
	auth.GasLimit = uint64(300000) // in units
	auth.GasPrice = gasPrice

	filNft, err := gen.NewFilNft(common.HexToAddress(cFilNftContract), client)
	if err != nil {
		log.Fatal(err)
	}

	bd := &bind.CallOpts{
		Pending:     false,
		From:        common.Address{},
		BlockNumber: nil,
		Context:     nil,
	}
	currNonce, err := filNft.CurrNonce(bd)
	if err != nil {
		log.Fatal(err)
	}
	dataMgr, err := filNft.DataMgr(bd)
	if err != nil {
		log.Fatal(err)
	}
	sysMgr, err := filNft.SysMgr(bd)
	if err != nil {
		log.Fatal(err)
	}

	currNonce = big.NewInt(0).Add(currNonce, big.NewInt(1))
	log.Print("nonce:" + currNonce.String())
	log.Print("datamgr:" + dataMgr.String())
	log.Print("sysmgr:" + sysMgr.String())

	stringTy, _ := abi.NewType("string", "", nil)

	uint256Ty, _ := abi.NewType("uint256", "", nil)

	// bytes32Ty, _ := abi.NewType("bytes32", "", nil)

	// bytesTy, _ := abi.NewType("bytes", "", nil)

	arguments := abi.Arguments{
		{
			Type: stringTy,
		},
		{
			Type: stringTy,
		},
		{
			Type: uint256Ty,
		},
		{
			Type: uint256Ty,
		},
	}

	nodeId := "f0123"
	uri := "http://test"
	size := big.NewInt(1000000000)
	bytes, err := arguments.Pack(
		nodeId,
		uri,
		size,
		currNonce,
	)
	if err != nil {
		log.Fatal(err)
	}

	h := hashText(bytes)
	hash := accounts.TextHash(h[:])

	sig, err := crypto.Sign(hash, encoderPriKey)
	if err != nil {
		log.Fatal(err)
	}
	// v := sig[64]
	if sig[64] < 27 {
		if sig[64] == 0 || sig[64] == 1 {
			sig[64] += 27
		} else {
			log.Fatal("signature invalid v byte")
		}
	}
	fmt.Printf("%x\n", h)
	fmt.Printf("%x\n", bytesTo32(hash))
	fmt.Printf("%x\n", sig)
	tx, err := filNft.Mint(&bind.TransactOpts{
		From:   crypto.PubkeyToAddress(ownerPriKey.PublicKey),
		Signer: auth.Signer,
	}, nodeId, uri, size, currNonce, bytesTo32(hash), sig)
	if err != nil {
		log.Fatal(err)
	}
	receipt, err := bind.WaitMined(context.Background(), client, tx)
	if err != nil {
		fmt.Println("WaitMined error", err)
	}
	fmt.Println(receipt.BlockNumber)
}
