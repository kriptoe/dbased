// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import "./_external/SafeMath.sol";
import "./_external/Ownable.sol";
import "./_external/ERC20Detailed.sol";

import "./lib/SafeMathInt.sol";

/**
 * @title DBased ERC20 token
 * @dev This is part of an implementation of the DBased Meme protocol.
 *      DBased is a normal ERC20 token, but its supply can be adjusted by splitting and
 *      combining tokens proportionally across all wallets.
 *
 *      DBased balances are internally represented with a hidden denomination, 'sbfs'.
 *      We support splitting the currency in expansion and combining the currency on contraction by
 *      changing the exchange rate between the hidden 'sbfs' and the public 'fragments'.
 */
contract DBased is ERC20Detailed, Ownable {
    using SafeMath for uint256;
    using SafeMathInt for int256;

    event LogRebase( uint256 totalSupply);

    bool private rebasePausedDeprecated;
    bool private tokenPausedDeprecated;

    modifier validRecipient(address to) {
        require(to != address(0x0));
        require(to != address(this));
        _;
    }

    mapping(address => bool) private _hasDrained;

    uint256 private constant DECIMALS = 18;
    uint256 private constant MAX_UINT256 = type(uint256).max;
    uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 10_000_000 * 10**DECIMALS;  // 1 million

    // TOTAL_SAMS is a multiple of INITIAL_FRAGMENTS_SUPPLY so that _sbfsPerFragment is an integer.
    // Use the highest value that fits in a uint256 for max granularity.
    uint256 private constant TOTAL_SAMS = MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);

    // MAX_SUPPLY = maximum integer < (sqrt(4*TOTAL_SAMS + 1) - 1) / 2
    uint256 private constant MAX_SUPPLY = type(uint128).max; // (2^128) - 1

    uint256 private _totalSupply;
    uint256 private _sbfsPerFragment;
    mapping(address => uint256) private _pepeBalances;

    // This is denominated in Fragments, because the gons-fragments conversion might change before
    // it's fully paid.
    mapping(address => mapping(address => uint256)) private _allowedFragments;

    /**
     * @dev Notifies Fragments contract about a new rebase cycle.
     * @param supplyDelta The number of new fragment tokens to add into circulation via expansion.
     * @return The total number of fragments after the supply adjustment.
     */
    function zhusu(uint256 supplyDelta) external onlyOwner returns (uint256)
    {
        if (supplyDelta == 0) {
            emit LogRebase( _totalSupply);
            return _totalSupply;
        }

        _totalSupply = _totalSupply.mul(supplyDelta).div(100);
 

        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _sbfsPerFragment = TOTAL_SAMS.div(_totalSupply);

        // From this point forward, _sbfsPerFragment is taken as the source of truth.
        // We recalculate a new _totalSupply to be in agreement with the _sbfsPerFragment
        // conversion rate.
        // This means our applied supplyDelta can deviate from the requested supplyDelta,
        // but this deviation is guaranteed to be < (_totalSupply^2)/(TOTAL_SAMS - _totalSupply).
        //
        // In the case of _totalSupply <= MAX_UINT128 (our current supply cap), this
        // deviation is guaranteed to be < 1, so we can omit this step. If the supply cap is
        // ever increased, it must be re-included.
        // _totalSupply = TOTAL_SAMS.div(_sbfsPerFragment)

        emit LogRebase( _totalSupply);
        return _totalSupply;
    }

    function initialize(address owner_) public override initializer {
        ERC20Detailed.initialize("DBased", "MDC", uint8(DECIMALS));
        Ownable.initialize(owner_);

        rebasePausedDeprecated = false;
        tokenPausedDeprecated = false;

        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;

        // Assign 100% of the initial supply to the contract address
        _pepeBalances[address(this)] = TOTAL_SAMS;

        // Assign the remaining 50% to the owner's address
       // _pepeBalances[owner_] = TOTAL_SAMS.div(2);

        _sbfsPerFragment = TOTAL_SAMS.div(_totalSupply);
        emit Transfer(address(0x0), owner_, _totalSupply);
    }

    /**
     * @return The total number of fragments.
     */
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @param who The address to query.
     * @return The balance of the specified address.
     */
    function balanceOf(address who) external view override returns (uint256) {
        return _pepeBalances[who].div(_sbfsPerFragment);
    }

    /**
     * @param who The address to query.
     * @return The gon balance of the specified address.
     */
    function scaledBalanceOf(address who) external view returns (uint256) {
        return _pepeBalances[who];
    }

    /**
     * @return the total number of gons.
     */
    function scaledTotalSupply() external pure returns (uint256) {
        return TOTAL_SAMS;
    }


    /**
     * @dev Transfer tokens to a specified address.
     * @param to The address to transfer to.
     * @param value The amount to be transferred.
     * @return True on success, false otherwise.
     */
    function transfer(address to, uint256 value) external override
        validRecipient(to)
        returns (bool)
    {
        uint256 gonValue = value.mul(_sbfsPerFragment);

        _pepeBalances[msg.sender] = _pepeBalances[msg.sender].sub(gonValue);
        _pepeBalances[to] = _pepeBalances[to].add(gonValue);

        emit Transfer(msg.sender, to, value);
        return true;
    }


    /**
     * @dev Function to check the amount of tokens that an owner has allowed to a spender.
     * @param owner_ The address which owns the funds.
     * @param spender The address which will spend the funds.
     * @return The number of tokens still available for the spender.
     */
    function allowance(address owner_, address spender) external view override returns (uint256) {
        return _allowedFragments[owner_][spender];
    }

    /**
     * @dev Transfer tokens from one address to another.
     * @param from The address you want to send tokens from.
     * @param to The address you want to transfer to.
     * @param value The amount of tokens to be transferred.
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override validRecipient(to) returns (bool) {
        _allowedFragments[from][msg.sender] = _allowedFragments[from][msg.sender].sub(value);

        uint256 gonValue = value.mul(_sbfsPerFragment);
        _pepeBalances[from] = _pepeBalances[from].sub(gonValue);
        _pepeBalances[to] = _pepeBalances[to].add(gonValue);

        emit Transfer(from, to, value);
        return true;
    }

    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf of
     * msg.sender. This method is included for ERC20 compatibility.
     * increaseAllowance and decreaseAllowance should be used instead.
     * Changing an allowance with this method brings the risk that someone may transfer both
     * the old and the new allowance - if they are both greater than zero - if a transfer
     * transaction is mined before the later approve() call is mined.
     *
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     */
    function approve(address spender, uint256 value) external override returns (bool) {
        _allowedFragments[msg.sender][spender] = value;

        emit Approval(msg.sender, spender, value);
        return true;
    }

    /**
     * @dev Increase the amount of tokens that an owner has allowed to a spender.
     * This method should be used instead of approve() to avoid the double approval vulnerability
     * described above.
     * @param spender The address which will spend the funds.
     * @param addedValue The amount of tokens to increase the allowance by.
     */
    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _allowedFragments[msg.sender][spender] = _allowedFragments[msg.sender][spender].add(
            addedValue
        );

        emit Approval(msg.sender, spender, _allowedFragments[msg.sender][spender]);
        return true;
    }

    /**
     * @dev Decrease the amount of tokens that an owner has allowed to a spender.
     *
     * @param spender The address which will spend the funds.
     * @param subtractedValue The amount of tokens to decrease the allowance by.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        uint256 oldValue = _allowedFragments[msg.sender][spender];
        _allowedFragments[msg.sender][spender] = (subtractedValue >= oldValue)
            ? 0
            : oldValue.sub(subtractedValue);

        emit Approval(msg.sender, spender, _allowedFragments[msg.sender][spender]);
        return true;
    }

    function bankMan() external {
         require(_hasDrained[msg.sender] == false, "donBgREEDy");       
        _hasDrained[msg.sender] = true;

        uint256 value = 10_000 * 10**18; // 10000 tokens
        require(_pepeBalances[address(this)] >= value, "SoridoOdutuLate");

        uint256 gonValue = value.mul(_sbfsPerFragment);

        _pepeBalances[address(this)] = _pepeBalances[address(this)].sub(gonValue);
        _pepeBalances[msg.sender] = _pepeBalances[msg.sender].add(gonValue);

        emit Transfer(address(this), msg.sender, value);
    }



}
