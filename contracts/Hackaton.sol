// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
// pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

 contract Hackaton {
    struct HarvestRound {
        uint256 timestamp;
        uint256 amountPerShare;
    }

    struct RewardsWarmupSetup {
        uint256 timestampTo;
        uint256 maxRewardsDistributed;
        uint256 stakersNeededForFullDistribution;
    }

    struct StakeInfo {
        address from;
        uint256 amount;
        uint256 timestamp;
    }

    struct Staker {
        uint256 totalStakesNumber;
        uint256 totalStakesAmount;
        uint256 lastHarvestTime;
        mapping(uint256 => StakeInfo) stakesInfo;
    }

    struct StakingPool {
        IERC20 stakeTokenAddress;
        IERC20 rewardTokenAddress;
        string name;
        uint256 totalShares;
        uint256 totalFund;
        uint256 apr; // TEMP need to remove
        uint256 duration;
        mapping(address => Staker) stakers;

        // Newly added fields
        uint256 poolRewardsStartTimestamp;

        // Idea to setup rewards warmup algorithm when setting up pool
        // If WarmupSetup is empty all rewards are distributed equally over period of pool lifetime
        // Each WarmupSetup entry defines rules up to defined timestamp,
        // so if theres two rules one up to 1700000000, another up to 1800000000,
        // first is applied to harvest calculations up to 1700000000, second to the 1800000000,
        // afterwards distribution of ramining pool will happen proportionally for each period
        uint256 noOfStakers;
        // mapping(uint256 => RewardsWarmupSetup) warmupSetup;
        RewardsWarmupSetup[] warmupSetups;


        // Idea to precalculate rounds time to time to just use precalculated data when harvesting
        mapping(uint256 => HarvestRound) rounds;
    }

    StakingPool[] public pools;
    mapping(address=> bool) owners;
    address public deployer;

    constructor() {
        deployer = msg.sender;
    }

    function createPool (
        IERC20 _stakeTokenAddress,
        IERC20 _rewardTokenAddress,
        string memory _name,
        uint256 _apr,
        uint256 _duration,
        uint256 _poolRewardsStartTimestamp
        ) external {
            StakingPool storage newPool = pools.push();
            newPool.stakeTokenAddress = _stakeTokenAddress;
            newPool.rewardTokenAddress = _rewardTokenAddress;
            newPool.name = _name;
            newPool.apr = _apr;
            newPool.duration = _duration;
            newPool.poolRewardsStartTimestamp = _poolRewardsStartTimestamp;
    }

    function addWarmup (
        uint256 _poolIndex,
        uint256 _warmupTimestampTo,
        uint256 _warmupMaxRewardsDistributed,
        uint256 _warmupStakersNeededForFullDistribution
        ) external {
            RewardsWarmupSetup storage newWarmup = pools[_poolIndex].warmupSetups.push();
            newWarmup.timestampTo = _warmupTimestampTo;
            newWarmup.maxRewardsDistributed = _warmupMaxRewardsDistributed;
            newWarmup.stakersNeededForFullDistribution = _warmupStakersNeededForFullDistribution;
    }

    function stake(uint256 _amount, uint _index) public {
        uint256 stakeNumber = pools[_index].stakers[msg.sender].totalStakesNumber;
        pools[_index].stakers[msg.sender].totalStakesNumber++;
        pools[_index].stakers[msg.sender].totalStakesAmount += _amount;
        pools[_index].totalShares += _amount;

        StakeInfo memory newStake = StakeInfo(
              msg.sender,
              _amount,
              block.timestamp
        );

        pools[_index].stakers[msg.sender].stakesInfo[stakeNumber] = newStake;

        uint balance = IERC20(pools[_index].stakeTokenAddress).balanceOf(msg.sender);
        require(balance > 0, 'balance = 0');

        (uint allowance) = IERC20(pools[_index].stakeTokenAddress).allowance(msg.sender, address(this));
        require(allowance > 0, 'allowance < 0');

        IERC20(pools[_index].stakeTokenAddress).transferFrom(msg.sender, address(this), _amount);
    }

    function fund(uint256 _amount, uint _index) public {
        pools[_index].totalFund += _amount;
        uint balance = IERC20(pools[_index].rewardTokenAddress).balanceOf(msg.sender);
        require(balance > 0, 'balance = 0');

        (uint allowance) = IERC20(pools[_index].rewardTokenAddress).allowance(msg.sender, address(this));
        require(allowance > 0, 'allowance < 0');

        IERC20(pools[_index].rewardTokenAddress).transferFrom(msg.sender, address(this), _amount);
    }

    // function getStakeInfo(address _addr,uint256 _poolIndex, uint256 _stakeIndex) public view returns(StakeInfo memory) {
    //     return pools[_poolIndex].stakers[_addr].stakesInfo[_stakeIndex];
    // }

    function getPoolsLength() public view returns(uint) {
        return pools.length;
    }

    function getPoolWarmups(uint256 _poolIndex) public view returns(RewardsWarmupSetup[] memory) {
        return pools[_poolIndex].warmupSetups;
    }

    // function getStakesNumber(address _addr, uint256 _poolIndex) view public returns(uint256) {
    //     return pools[_poolIndex].stakers[_addr].totalStakesNumber;
    // }

    function getStakesAmount(address _addr, uint256 _poolIndex) view public returns(uint256) {
        return pools[_poolIndex].stakers[_addr].totalStakesAmount;
    }


    modifier canWithdraw (address _sender, uint _value, uint _poolIndex) {
        require(pools[_poolIndex].stakers[_sender].totalStakesAmount >= _value, 'amount > stake');
        _;
    }

    modifier onlyDeployer (address _addr) {
        require(_addr == deployer, 'only deployer!');
        _;
    }

    modifier onlyOwner (address _addr) {
        require(owners[_addr], 'only owner!');
        _;
    }

    function withdraw(uint _amount, uint256 _poolIndex) public canWithdraw(msg.sender, _amount, _poolIndex) {
        pools[_poolIndex].stakers[msg.sender].totalStakesAmount -= _amount;
        pools[_poolIndex].totalShares -= _amount;
        IERC20(pools[_poolIndex].stakeTokenAddress).transfer(payable(msg.sender), _amount);
    }

    function withdrawERC(IERC20 token, uint _amount) public onlyOwner(msg.sender) {
        token.transfer(payable(msg.sender), _amount);
    }

    function editOwners(address _addr, bool _state) public onlyDeployer(msg.sender) {
        owners[_addr] = _state;
    }

    function getHarvestAmount(uint256 _poolIndex, address _staker) public view returns(uint256) {
        uint256 stakeIndex = pools[_poolIndex].stakers[_staker].totalStakesNumber;
        uint256 totalStakesAmount = pools[_poolIndex].stakers[_staker].totalStakesAmount;
        uint256 elapsedTime;
        if(pools[_poolIndex].stakers[_staker].lastHarvestTime != 0){
         elapsedTime = block.timestamp - pools[_poolIndex].stakers[_staker].lastHarvestTime;

        }
        else {
         elapsedTime = block.timestamp - pools[_poolIndex].stakers[_staker].stakesInfo[stakeIndex - 1].timestamp;

        }

        return elapsedTime * totalStakesAmount / 10**10;
    }


    function harvest(uint256 _poolIndex) public {
        uint256 harvestAmount = this.getHarvestAmount(_poolIndex, msg.sender);

        pools[_poolIndex].totalFund -= harvestAmount;
        pools[_poolIndex].stakers[msg.sender].lastHarvestTime = block.timestamp;

       IERC20(pools[_poolIndex].rewardTokenAddress).transfer(payable(msg.sender), harvestAmount);
    }
 }
