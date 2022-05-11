// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;


import "IERC20.sol";
import "Ownable.sol";
import "SafeMath.sol";
import "ABDKMathQuad.sol";

 contract LiquidityFarming is Ownable {
  using SafeMath for uint256;

  address[] internal lockableToken;

  mapping(address => IERC20) internal token;

  mapping(address => bool) internal isLockableToken;

  mapping(address => uint256) public totalLocked;

  mapping(address => uint256) public totalScore;

  mapping(address => uint256) public blockReward;

  mapping(address => uint256) internal stakeBlock;

  mapping(address => bytes16) internal rewardRatio;

  mapping(address => mapping(address => address)) internal lockerAddress;

  mapping(address => mapping (address => uint256)) public lockPermanentAmount;

  mapping(address => mapping (address => uint256)) public lockTimedAmount;

  mapping(address => mapping (address => uint256)) public lockTime;

  mapping(address => mapping (address => uint256)) public timeLockingPeriod;

  mapping(address => mapping (address => uint256)) public userScore;

  mapping(address => mapping(address => bytes16)) internal userRewardRatio;

  uint256[] public timeLockingPeriods;

  mapping(uint256 => uint256) public timeBonus;

  uint256 public totalRewardsMinted;

  uint256 public rewardTax;

  uint256 internal treasury;

  TokenInterface TKN;

  address LGE;

    constructor() {
        address token_TKN = address(0x0);
        TKN = TokenInterface(token_TKN);
        LGE = address(0x0);
        rewardTax = 8;
        timeLockingPeriods = [0, 2592000, 7776000, 15552000, 31104000];
        uint8[5] memory _timeBonus = [0, 5, 10, 20, 35];
        for (uint256 s = 0; s < _timeBonus.length; s += 1){
          timeBonus[timeLockingPeriods[s]] = _timeBonus[s];
        }
    }

  function addLockablePair(address _pair, uint256 _blockReward)
  public
  onlyOwner
  {
    require(!isLockableToken[_pair], "Token already added!");
    lockableToken.push(_pair);
    isLockableToken[_pair] = true;
    token[_pair] = IERC20(_pair);
    blockReward[_pair] = _blockReward;
  }

  function adjustBlockReward(address _pair, uint256 _blockReward)
  external
  onlyOwner
  {
    require(isLockable(_pair), "This token has not been added!");
    calculateRewardRatio(_pair);
    blockReward[_pair] = _blockReward;
  }

  function adjustRewardTax(uint256 _rewardTax)
  external
  onlyOwner
  {
    require(rewardTax < 10, "Enter tax between 0-10%!");
    rewardTax = _rewardTax;
  }

  function removeRewardEmissions()
  external
  onlyOwner
  {
    for (uint256 s = 0; s < lockableToken.length; s += 1){
      calculateRewardRatio(lockableToken[s]);
      blockReward[lockableToken[s]] = 0;
    }

  }

  function isLockable(address _token)
  public
  view
  returns(bool)
  {
    return (isLockableToken[_token]);
  }

  function isLocker(address _pair, address _address)
  public
  view
  returns(bool)
  {
    if (_address == lockerAddress[_pair][_address]) return (true);
    return (false);
  }

  function lockPermanent(address _token, uint256 _amount)
  external
  {
    require(isLockable(_token), "Token not accepted!");
    require(token[_token].transferFrom(msg.sender, address(this), _amount), "No funds received!");
    pushLiquidityData(_token, msg.sender, _amount, true, 0);
  }

  function lockTimed(address _token, uint256 _amount, uint256 _time)
  external
  {
    require(isLockable(_token), "Token not accepted!");
    bool validTimePeriod = false;
    for (uint256 s = 0; s < timeLockingPeriods.length; s += 1){
      if(timeLockingPeriods[s] == _time) validTimePeriod = true;
    }
    require(validTimePeriod, "Please choose a valid time period!");
    require(lockTime[_token][msg.sender] < _time.add(block.timestamp), "Locking time cannot be shorter than for previous lock!");
    require(token[_token].transferFrom(msg.sender, address(this), _amount), "No funds received!");

    pushLiquidityData(_token, msg.sender, _amount, false, _time);
    lockTime[_token][msg.sender] = _time.add(block.timestamp);
}

  function pushLiquidityData(address _token, address _stakeholder, uint256 _amount, bool _permanent, uint256 _time)
  internal
  {//uint256 reward = rewardOf(_token, _stakeholder);
    if(totalLocked[_token] == 0) stakeBlock[_token] = block.number;
    else calculateRewardRatio(_token);

    if(!isLocker(_token, _stakeholder)){
      lockerAddress[_token][_stakeholder] = _stakeholder;
      totalLocked[_token] = totalLocked[_token].add(_amount);
      userRewardRatio[_token][_stakeholder] = rewardRatio[_token];
    }
    else {
      uint256 reward = rewardOf(_token, _stakeholder);
      totalLocked[_token] = totalLocked[_token].add(_amount);
      userRewardRatio[_token][_stakeholder] = rewardRatio[_token];
      distributeReward(_stakeholder, reward);
    }



    if(_permanent){
      userScore[_token][_stakeholder] = userScore[_token][_stakeholder].add(_amount.mul(2));
      totalScore[_token] = totalScore[_token].add(_amount.mul(2));
      lockPermanentAmount[_token][_stakeholder] = lockPermanentAmount[_token][_stakeholder].add(_amount);
    }
    else {
      if(lockTimedAmount[_token][_stakeholder] > 0){
        userScore[_token][_stakeholder] = userScore[_token][_stakeholder].sub(lockTimedAmount[_token][_stakeholder].add(lockTimedAmount[_token][_stakeholder].mul(timeBonus[timeLockingPeriod[_token][_stakeholder]]).div(100)));
        totalScore[_token] = totalScore[_token].sub(lockTimedAmount[_token][_stakeholder].add(lockTimedAmount[_token][_stakeholder].mul(timeBonus[timeLockingPeriod[_token][_stakeholder]]).div(100)));

      }
      lockTimedAmount[_token][_stakeholder] = lockTimedAmount[_token][_stakeholder].add(_amount);
      timeLockingPeriod[_token][msg.sender] = _time;
      userScore[_token][_stakeholder] = userScore[_token][_stakeholder].add(lockTimedAmount[_token][_stakeholder].add(lockTimedAmount[_token][_stakeholder].mul(timeBonus[timeLockingPeriod[_token][_stakeholder]]).div(100)));
      totalScore[_token] = totalScore[_token].add(lockTimedAmount[_token][_stakeholder].add(lockTimedAmount[_token][_stakeholder].mul(timeBonus[timeLockingPeriod[_token][_stakeholder]]).div(100)));

    }
  }

  function pushLockFromLGE(address _liquidityToken, uint256 _totalLiquidityTokenAmount, address[] memory investors, uint256[] memory tokenAmount)
  external
  {
    require(msg.sender == LGE, "Function can only be called by the Liquidity Generation Event contract!");
    addLockablePair(_liquidityToken, 1000000000000000000); // Token addresses and block reward
    require(isLockable(_liquidityToken), "Token not accepted!");
    require(token[_liquidityToken].transferFrom(msg.sender, address(this), _totalLiquidityTokenAmount), "No funds received!");

    if(totalLocked[_liquidityToken] == 0) {
      stakeBlock[_liquidityToken] = block.number;
    }
    else {
      calculateRewardRatio(_liquidityToken);
    }
    for (uint256 s = 0; s < investors.length; s += 1){
        pushLiquidityData(_liquidityToken, investors[s], tokenAmount[s], false, 15552000);
    }

  }

    function pushLGEAddress(address _LGE) external onlyOwner {
      LGE = _LGE;
    }

  function blocksStaked(address _token)
  private
  view
  returns(uint256)
  {
    return  block.number.sub(stakeBlock[_token]);
  }

  function rewardOf(address _token, address _stakeholder)
  public
  view
  returns(uint256 totalRewards)
  {
    uint256 totalUserScore = userScore[_token][_stakeholder];
    totalRewards = ABDKMathQuad.toUInt(ABDKMathQuad.mul(ABDKMathQuad.fromUInt(totalUserScore), ABDKMathQuad.sub(rewardRatio[_token], userRewardRatio[_token][_stakeholder])));

    return totalRewards;
  }

  function getTotalScore(address _token) internal view returns (uint256 _totalScore){
    _totalScore = totalScore[_token];
  }

  function calculateRewardRatio(address _pair)
  public
  {
    uint256 accumulatedRewards = blockReward[_pair].mul(blocksStaked(_pair));
    rewardRatio[_pair] = ABDKMathQuad.add(rewardRatio[_pair], ABDKMathQuad.div(ABDKMathQuad.fromUInt(accumulatedRewards), ABDKMathQuad.fromUInt(getTotalScore(_pair))));
    stakeBlock[_pair] = block.number;
  }

  /**
  * @notice A method to distribute reward to .
  */
  function distributeReward(address _stakeholder, uint256 _reward)
  internal
  {
    uint256 tax = _reward.mul(rewardTax).div(100);
    TKN.mint(_stakeholder, _reward.sub(tax));
    TKN.mint(address(this), tax);
    totalRewardsMinted = totalRewardsMinted.add(_reward);
    treasury = treasury.add(tax);
  }

  /**
  * @notice A method to allow a stakeholder to withdraw his rewards.
  */
  function withdrawReward(address _token)
  external
  {
    require(lockTimedAmount[_token][msg.sender] > 0 || lockPermanentAmount[_token][msg.sender] > 0, "No active stake found!");

    calculateRewardRatio(_token);
    uint256 reward = rewardOf(_token, msg.sender);
    userRewardRatio[_token][msg.sender] = rewardRatio[_token];
    totalRewardsMinted = totalRewardsMinted.add(reward);
    uint256 tax = reward.mul(rewardTax).div(100);
    TKN.mint(msg.sender, reward.sub(tax));
    TKN.mint(address(this), tax);
    treasury = treasury.add(tax);


  }

  function treasuryReward(address _address, uint256 _amount)
  external
  onlyOwner
  {
    require(_amount <= treasury, "Amount exceeds balance!");
    TKN.transfer(_address, _amount);
  }

  function withdrawLiquidity(address _token, uint256 _amount)
  external
  {
    require(lockTime[_token][msg.sender] < block.timestamp, "Lock time not over!");
    require(_amount <= lockTimedAmount[_token][msg.sender], "Amount exceeds balance!");
    calculateRewardRatio(_token);
    uint256 reward = rewardOf(_token, msg.sender);

    totalLocked[_token] = totalLocked[_token].sub(_amount);
    lockTimedAmount[_token][msg.sender] = lockTimedAmount[_token][msg.sender].sub(_amount);
    userRewardRatio[_token][msg.sender] = rewardRatio[_token];
    //
    totalScore[_token] = totalScore[_token].sub(_amount.add(_amount.mul(timeBonus[timeLockingPeriod[_token][msg.sender]]).div(100)));
    userScore[_token][msg.sender] = userScore[_token][msg.sender].sub(_amount.add(_amount.mul(timeBonus[timeLockingPeriod[_token][msg.sender]]).div(100)));
    distributeReward(msg.sender, reward);
    token[_token].transfer(msg.sender, _amount);

  }

}

interface TokenInterface {
    function mint(address to, uint256 amount) external;
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}
