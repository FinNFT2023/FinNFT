// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import "openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/Counters.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

import "./Common.sol";

abstract contract FilNftDataLayout {
    using Counters for Counters.Counter;

    uint32 constant INCOME_RELEASE_CYCLE = 180;
    uint32 constant INCOME_LOCK = 75;

    struct NodeNft {
        bool valid;
        uint256 size;
        uint256 free;
    }

    struct UserNft {
        uint256 deadline;
        uint256 start_index;
        uint256 size;
        uint256 free;
        uint256 proportion;
        uint256 withdraw;
    }

    struct UserNftInNode {
        uint256 tokenId;
        uint256 size;
        uint256 deadline;
    }

    struct RRecord {
        uint256 r;
        uint256 sum_r;
        uint256 sum_nr;
    }

    address internal _owner;
    address internal _sysMgr;
    address internal _dataMgr;
    uint256 internal _createDate;

    mapping(uint256 => UserNft) public _userNfts;
    mapping(uint256 => NodeNft) public _nodeNfts;
    mapping(uint256 => UserNftInNode[]) internal _nodeDatas; 
    mapping(address => Counters.Counter) internal _nonces;

    RRecord[] public _rRecords;
    Counters.Counter internal _counter;

    modifier onlyOwner() {
        require(msg.sender == _owner, "Permission denied");
        _;
    }

    modifier onlySysMgr() {
        require(msg.sender == _sysMgr, "Permission denied");
        _;
    }

    modifier onlyDataMgr() {
        require(msg.sender == _dataMgr, "Permission denied");
        _;
    }

    function owner() public view returns(address) {
        return _owner;
    }

    function setOwner(address addr) public onlyOwner {
        _owner = addr;
    }

    function sysMgr() public view returns(address) {
        return _sysMgr;
    }

    function setSysMgr(address addr) public onlyOwner {
        _sysMgr = addr;
    }

    function dataMgr() public view returns(address) {
        return _dataMgr;
    }

    function setDataMgr(address addr) public onlyOwner {
        _dataMgr = addr;
    }

    function genTokenId() internal returns (uint256) {
        _counter.increment();
        return _counter.current();
    }

    function currNonce(address addr) public view returns (uint256) {
        return _nonces[addr].current();
    }

    function nextNonce(address addr) internal {
        _nonces[addr].increment();
    }

    function getNodeDatas(string memory nodeid) public view returns (UserNftInNode[] memory) {
        uint256 tokenId = uint256(bytes32(keccak256(abi.encode(nodeid))));
        return _nodeDatas[tokenId];
    }
}

contract FilNft is FilNftDataLayout, ERC721URIStorageUpgradeable {
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignatureChecker for address;
    using ECDSA for bytes32;

    event SetR(uint256, uint256);
    event Operate(bytes32, uint256);

    function initialize(
        string memory name,
        string memory symbol,
        address sysMgr,
        address dataMgr
    ) public initializer 
    {
        __ERC721_init_unchained(name, symbol);

        _owner = msg.sender;
        _sysMgr = sysMgr;
        _dataMgr = dataMgr;

        _createDate = getTodayIndex();
    }

    // mint fil.node.nft
    function mint(MintNodeNftParams calldata params) 
        public checkSign(params.hash, params.signature) checkNonce(params.nonce) 
    {
        _paramsVerify(params);
        
        uint256 tokenId = uint256(bytes32(keccak256(abi.encode(params.nodeId))));

        NodeNft memory nodeNft;
        nodeNft.valid = true;
        nodeNft.size = params.size;
        nodeNft.free = params.size;
        _nodeNfts[tokenId] = nodeNft;

        _safeMint(msg.sender, tokenId);

        _setTokenURI(tokenId, params.uri);

        emit Operate(params.hash, tokenId);
    }

    function _paramsVerify(MintNodeNftParams calldata params) internal pure {
        bytes32 ethMsgHash = keccak256(
            abi.encode(params.nodeId, params.uri, params.size, params.nonce)
        ).toEthSignedMessageHash();
        require(params.hash == ethMsgHash, "signature hash verify failed");
    }

    // mint fil.user.nft
    function mint(MintUserNft calldata params) 
        public checkSign(params.hash, params.signature) checkNonce(params.nonce) 
    {
        _paramsVerify(params);

        uint256 tokenId = genTokenId();

        {
            uint256 todayIndex = getTodayIndex();
            uint256 deadlineIndex = todayIndex - _createDate + params.deadline;
            _userNfts[tokenId].size = updateNodeData(params.nodeids, params.sizes, tokenId, todayIndex - _createDate, deadlineIndex);
            _userNfts[tokenId].start_index = todayIndex - _createDate;
            _userNfts[tokenId].deadline = deadlineIndex;
            _userNfts[tokenId].proportion = params.proportion; 
        }

        if (params.useraddr != address(0x0)) {
            _safeMint(params.useraddr, tokenId);
        } else {
            _safeMint(msg.sender, tokenId);
        }

        _setTokenURI(tokenId, params.uri);

        emit Operate(params.hash, tokenId);
    }

    function _paramsVerify(MintUserNft calldata params) internal pure {
        require(params.proportion <= 100, "proportion set error");
        require(params.nodeids.length == params.sizes.length, "nodeids or sizes set error");

        bytes32 ethMsgHash = keccak256(
            abi.encode(params.uri, params.deadline, params.nodeids, params.sizes, params.nonce, params.proportion, params.useraddr)
        ).toEthSignedMessageHash();
        require(params.hash == ethMsgHash, "signature hash verify failed");
    }

    function burn(BurnParams calldata params) 
        public checkSign(params.hash, params.signature) checkNonce(params.nonce) 
    {

        _paramsVerify(params);

        uint tokenId = uint(keccak256(abi.encode(params.nodeId)));
        _requireMinted(tokenId);
        require(_nodeNfts[tokenId].valid, "node not exist");
        require(_ownerOf(tokenId) == msg.sender, "not nft owner");

        UserNftInNode[] memory nodeDatas = _nodeDatas[tokenId];
        uint cur = getTodayIndex() - _createDate;
        for (uint i; i < nodeDatas.length; i++) {
            require(cur > nodeDatas[i].deadline, "exist not expired user nft");
        }

        _burn(tokenId);

        delete _nodeNfts[tokenId];
        delete _nodeDatas[tokenId];
        emit Operate(params.hash, tokenId);
    }

    function _paramsVerify(BurnParams calldata params) internal pure {
        bytes32 ethMsgHash = keccak256(abi.encode(params.nodeId, params.nonce))
            .toEthSignedMessageHash();
        require(params.hash == ethMsgHash, "signature hash verify failed");
    }

    function setR(uint256 r) public onlyDataMgr {
        uint256 index = getTodayIndex() - _createDate;
        _setR(index, r);
        emit SetR(index, r);
    }

    function setR(uint256 index, uint256 r) public onlyDataMgr {
        require(
            index <= getTodayIndex() - _createDate,
            "input index too large"
        );
        require(
            index > getTodayIndex() - _createDate - 3,
            "input index too small"
        );

        _setR(index, r);
        emit SetR(index, r);
    }

    function withdraw(WithdrawParams calldata params) 
        public checkSign(params.hash, params.signature) checkNonce(params.nonce) {

        _requireMinted(params.tokenId);

        require(_ownerOf(params.tokenId) == msg.sender, "not nft owner");

        bytes32 msgHash = keccak256(abi.encode(params.tokenId, params.amount, params.nonce));
        require(params.hash == msgHash.toEthSignedMessageHash(), "manager sign error");

        UserNft storage userNft = _userNfts[params.tokenId];
        require(params.amount <= getWithdraw(params.tokenId), "not enough income");

        userNft.withdraw += params.amount;
        emit Operate(params.hash, params.amount);
    }

    function getWithdraw(uint256 tokenId) public view returns (uint256) {
        _requireMinted(tokenId);

        UserNft memory userNft = _userNfts[tokenId];

        return getAllIncome(tokenId) - getLockIncome(tokenId) - userNft.withdraw;
    }

    function updateNodeData(
        string[] memory nodeids,
        uint256[] memory sizes,
        uint256 tokenId,
        uint256 cur,
        uint256 _deadline
    ) internal returns (uint) {
        uint allSize;
        for (uint256 i; i < nodeids.length; i++) {
            uint256 nodeTokenId = uint256(
                bytes32(keccak256(abi.encode(nodeids[i])))
            );

            require(_nodeNfts[nodeTokenId].valid, "node not exist");

            NodeNft storage nodeNft = _nodeNfts[nodeTokenId];
            UserNftInNode[] storage nodeDatas = _nodeDatas[nodeTokenId];

            UserNftInNode memory nd;
            nd.tokenId = tokenId;
            nd.size = sizes[i];
            nd.deadline = _deadline;

            if (nodeNft.free > sizes[i]) {
                nodeDatas.push(nd);
            } else {
                uint256 dl_index;
                for (uint256 j; j < nodeDatas.length; j++) {
                    if (cur > nodeDatas[j].deadline) {
                        dl_index = j;
                        nodeNft.free += nodeDatas[j].size;
                    }

                    if (nodeNft.free > sizes[i]) {
                        break;
                    }
                }

                require(nodeNft.free >= sizes[i], "input sizes error");

                nodeDatas[dl_index] = nd;
            }

            nodeNft.free -= sizes[i];
            allSize += sizes[i];
        }

        return allSize;
    }

    function getLockIncome(uint256 tokenId) public view returns (uint256) {
        _requireMinted(tokenId);

        if (_rRecords.length == 0) {
            return 0;
        }

        UserNft memory userNft = _userNfts[tokenId];

        uint256 cur = _rRecords.length - 1;
        uint256 start = userNft.start_index;
        uint256 dl = userNft.deadline;
        uint256 rd = INCOME_RELEASE_CYCLE;
        uint256 size = userNft.size;
        uint256 p = userNft.proportion;

        if (cur <= start || cur > dl + rd) {
            return 0;
        }

        int256 j = cur.toInt256() - rd.toInt256() - 1;
        uint256 k = start - 1;
        if (cur > start + rd) {
            k = j.toUint256();
        }

        uint256 sum_rs;
        uint256 sum_nrs;
        if (cur > dl) {
            sum_rs = _rRecords[dl - 1].sum_r - _rRecords[k].sum_r;
            sum_nrs = _rRecords[dl - 1].sum_nr - _rRecords[k].sum_nr;
        } else {
            sum_rs = _rRecords[cur - 1].sum_r - _rRecords[k].sum_r;
            sum_nrs = _rRecords[cur - 1].sum_nr - _rRecords[k].sum_nr;
        }

        uint256 lock = (sum_nrs.toInt256() - j * sum_rs.toInt256()).toUint256();

        // 1TB = (1 << 40) * B，nft存储算力单位转换。_INCOME_LOCK 和 p应该是小数。
        return (lock * INCOME_LOCK * size * p) / rd / 100 / 100 / (1 << 40);
    }

    function getAllIncome(uint256 tokenId) public view returns (uint256) {
        _requireMinted(tokenId);
        if (_rRecords.length == 0) {
            return 0;
        }

        UserNft memory userNft = _userNfts[tokenId];
        uint256 cur = _rRecords.length - 1;
        uint256 start = userNft.start_index;
        uint256 dl = userNft.deadline;
        uint256 size = userNft.size;
        uint256 p = userNft.proportion;
        
        if (cur <= start) {
            return 0;
        }

        uint256 sum_rs;
        if (cur > dl) {
            sum_rs = _rRecords[dl - 1].sum_r - _rRecords[start - 1].sum_r;
        } else {
            sum_rs = _rRecords[cur - 1].sum_r - _rRecords[start - 1].sum_r;
        }

        return (sum_rs * size * p) / 100 / (1 << 40);
    }

    function _setR(uint256 index, uint256 r) internal {
        if (index != 0 && index > _rRecords.length) {
            _setR(index - 1, 0);
        }

        RRecord memory prev;
        RRecord memory curr;
        if (index != 0) {
            prev = _rRecords[index - 1];
        }

        curr.r = r;
        curr.sum_r = prev.sum_r + r;
        curr.sum_nr = prev.sum_nr + (index + 1) * r;

        if (index == 0 || index == _rRecords.length) {
            _rRecords.push(curr);
        } else {
            _rRecords[index] = curr;
            for (uint256 i = index + 1; i < _rRecords.length; i++) {
                _rRecords[i].sum_r = _rRecords[i - 1].sum_r + _rRecords[i].r;
                _rRecords[i].sum_nr =
                    _rRecords[i - 1].sum_nr +
                    (i + 1) *
                    _rRecords[i].r;
            }
        }
    }

    function getTodayIndex() internal view returns (uint256) {
        return block.timestamp / 24 / 3600;
    }

    function isValidSignatureNow(
        address signer,
        bytes32 _hash,
        bytes memory signature
    ) internal view returns (bool) {
        return signer.isValidSignatureNow(_hash, signature);
    }

    modifier checkSign(bytes32 _hash, bytes memory signature) {
        require(
            isValidSignatureNow(_sysMgr, _hash, signature),
            "check signature failed"
        );
        _;
    }

    modifier checkNonce(uint256 nonce) {
        require(nonce == currNonce(msg.sender) + 1, "nonce error");
        _;
        nextNonce(msg.sender);
    }
}
