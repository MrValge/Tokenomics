pragma solidity ^0.7.0;

import "SafeMath.sol";
import "Ownable.sol";
import "LivePriceETH.sol";

contract LGE is Ownable, LivePrice {
    using SafeMath for uint256;

    address[] internal investor;
    mapping(address => bool) internal investorBool;
    mapping(address => uint256) public amount;
    mapping(address => uint256) internal score;

    uint256 public totalRaised;
    uint256 public endTime;

    mapping(address => uint256) allowed;
    uint256 internal availableBalance;

    PreLGEInterface preLGE1;
    PreLGEInterface preLGE2;
    PreLGEInterface preLGE3;
    UniSwapRouter UniSwap;
    UniSwapFactory Factory;
    SWNInterface SWN;
    LiquidityLock LiquidityContract;
    uint256 oracleValueDivisor;
    uint256 maxMintableSWN;
    uint256 decimals;

    constructor() {
      endTime = block.timestamp.add(1210000); // Open for Two Weeks
      preLGE1 = PreLGEInterface(0x0);
      preLGE2 = PreLGEInterface(0x0);
      preLGE3 = PreLGEInterface(0x0);
      UniSwap = UniSwapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
      Factory = UniSwapFactory(UniSwap.factory());
      oracleValueDivisor = 10**8;
      decimals = 10**18;
      maxMintableSWN = decimals.mul(5000000);
    }

    function invest(address _investor) external payable {
        require(block.timestamp < endTime, "Liquidity Generation Event is closed!");
        require(msg.value > 0, "No ETH sent!");
        uint256 currentPrice = uint(getLatestPrice());
        if (!investorBool[_investor]) {
          investor.push(_investor);
          investorBool[_investor] = true;
        }
        amount[_investor] = amount[_investor].add(msg.value);
        totalRaised = totalRaised.add(msg.value);
        availableBalance = availableBalance.add(msg.value.div(2));

        uint256 currentScore = currentPrice.mul(msg.value).div(oracleValueDivisor);
        score[_investor] = score[_investor].add(currentScore);
      }

    function isInvestor(address _address)
        public
        view
        returns(bool)
    {
      return(investorBool[_address]);
    }
    function getInvestors()
        external
        view
        returns(address[] memory)
    {
        return investor;
    }

    function getScores() external view returns (uint256[] memory) {
      uint256[] memory scores = new uint256[](investor.length);
      for (uint256 s = 0; s < investor.length; s += 1){
        scores[s] = score[investor[s]];
      }
      return scores;
    }

    function getTotalScore() public view returns (uint256 totalScore) {
      for (uint256 s = 0; s < investor.length; s += 1){
        totalScore = totalScore.add(score[investor[s]]);
      }
    }

    function endLGE(uint256 _swapSlippage) external onlyOwner {
      endTime = block.timestamp;

      uint256 amountETH = totalRaised.div(2);
      uint256 currentPrice = uint(getLatestPrice());
      uint256 amountSWN = amountETH.mul(currentPrice).mul(5).div(oracleValueDivisor);
      if(amountSWN > maxMintableSWN) amountSWN = maxMintableSWN;
      SWN.mint(address(this), amountSWN);
      SWN.approve(address(UniSwap), amountSWN);
      (, , uint256 amountLP) = UniSwap.addLiquidityETH(address(SWN), amountSWN, amountSWN.mul(95).div(100), amountETH.mul(95).div(100), address(this), block.timestamp.add(180));
      address liquidityToken = Factory.getPair(address(SWN), Uniswap.WETH());
      pushLiquidity(liquidityToken, amountLP);
    }

    function pushLiquidity(address liquidityToken, uint256 amountLP) internal {
        (address[] memory LGEInvestors, uint256[] memory LGEScores) = concatenateInvestorArrays();
        uint256 totalLGEScore = getTotalScore().add(preLGE1.getTotalScore().add(preLGE2.getTotalScore().add(preLGE3.getTotalScore())));
        TokenInterface liqToken = TokenInterface(liquidityToken);
        liqToken.approve(address(LiquidityContract), amountLP);
        LiquidityContract.pushLockFromLGE(liquidityToken, amountLP, LGEInvestors, individualLiquidityTokenAmount(amountLP, totalLGEScore, LGEScores));

    }

    function concatenateInvestorArrays() internal returns(address[] memory, uint256[] memory){
      address[] memory LGEInvestors1 = preLGE1.getInvestors();
      uint256[] memory LGEScores1 = preLGE1.getScores();
      uint256 length1 = LGEInvestors1.length;
      address[] memory LGEInvestors2 = preLGE2.getInvestors();
      uint256[] memory LGEScores2 = preLGE2.getScores();
      uint256 length2 = LGEInvestors2.length;
      address[] memory LGEInvestors3 = preLGE3.getInvestors();
      uint256[] memory LGEScores3 = preLGE3.getScores();
      uint256 length3 = LGEInvestors3.length;
      uint256 length4 = investor.length;
      address[] memory investorArray = new address[](length1.add(length2.add(length3.add(length4))));
      uint256[] memory scoreArray = new uint256[](length1.add(length2.add(length3.add(length4))));
      for (uint256 s = 0; s < length1; s += 1){
        investorArray[s] = LGEInvestors1[s];
        scoreArray[s] = LGEScores1[s];
      }
      for (uint256 s = 0; s < length2; s += 1){
        investorArray[length1 + s] = LGEInvestors2[s];
        scoreArray[length1 + s] = LGEScores2[s];
      }
      for (uint256 s = 0; s < length3; s += 1){
        investorArray[length1 + length2 + s] = LGEInvestors3[s];
        scoreArray[length1 + length2 + s] = LGEScores3[s];
      }
      for (uint256 s = 0; s < length4; s += 1){
        investorArray[length1 + length2 + length3 + s] = investor[s];
        scoreArray[length1 + length2 + length3 + s] = score[investor[s]];
      }
      return(investorArray, scoreArray);
    }

    function individualLiquidityTokenAmount(uint256 _totalLiquidityTokensCreated, uint256 totalScore, uint256[] memory scores)
    internal
    pure
    returns(uint256[] memory)
    {
      uint256[] memory liquidityTokens = new uint256[](scores.length);
      for (uint256 s = 0; s < scores.length; s += 1){
          liquidityTokens[s] =  _totalLiquidityTokensCreated.div(totalScore.div(scores[s]));
      }
      return liquidityTokens;
    }

    function pushInterfaceAddresses(address _SWN, address _liquidity) external onlyOwner {
      SWN = SWNInterface(_SWN);
      LiquidityContract = LiquidityLock(_liquidity);
    }

    function approveFor(address _address, uint256 _amount) external onlyOwner {
      allowed[_address] = allowed[_address].add(_amount);
    }

    function withdraw(address payable _to, uint256 _amount)
    external
    {
      require(_amount <= availableBalance, "Amount larger than available!");
      require(allowed[_to] >= _amount, "Allowance exceeded!");
      allowed[_to] = allowed[_to].sub(_amount);
      availableBalance = availableBalance.sub(_amount);
        (bool sent,) = _to.call{value: _amount}("");
        require(sent, "Failed to send Ether");
    }

    receive() external payable {}
}

interface PreLGEInterface {
  function getInvestors() external returns(address[] memory);
  function getScores() external returns (uint256[] memory);
  function getTotalScore() external returns (uint256);
}

interface UniSwapRouter {
  function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
    external
    payable
    returns (uint[] memory amounts);
function addLiquidityETH(
  address token,
  uint amountTokenDesired,
  uint amountTokenMin,
  uint amountETHMin,
  address to,
  uint deadline
) external payable returns (uint amountToken, uint amountETH, uint liquidity);
  function WETH() external returns(address);
  function factory() external pure returns (address);
}
interface UniSwapFactory {
  function getPair(address tokenA, address tokenB) external view returns (address pair);
}
interface SWNInterface {
  function mint(address to, uint256 amount) external;
  function approve(address spender, uint256 amount) external returns(bool);
}
interface LiquidityLock {
  function pushLockFromLGE(address _liquidityToken, uint256 _totalLiquidityTokenAmount, address[] memory investors, uint256[] memory tokenAmount) external;
}
interface TokenInterface {
    function transferFrom(address from, address to, uint256 amount) external returns(bool);
    function approve(address spender, uint256 amount) external returns(bool);
}
