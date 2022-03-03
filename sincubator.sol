// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.4;

library LowGasSafeMath {
    /// @notice Returns x + y, reverts if sum overflows uint256
    /// @param x The augend
    /// @param y The addend
    /// @return z The sum of x and y
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    function add32(uint32 x, uint32 y) internal pure returns (uint32 z) {
        require((z = x + y) >= x);
    }

    /// @notice Returns x - y, reverts if underflows
    /// @param x The minuend
    /// @param y The subtrahend
    /// @return z The difference of x and y
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    function sub32(uint32 x, uint32 y) internal pure returns (uint32 z) {
        require((z = x - y) <= x);
    }

    /// @notice Returns x * y, reverts if overflows
    /// @param x The multiplicand
    /// @param y The multiplier
    /// @return z The product of x and y
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(x == 0 || (z = x * y) / x == y);
    }

    /// @notice Returns x + y, reverts if overflows or underflows
    /// @param x The augend
    /// @param y The addend
    /// @return z The sum of x and y
    function add(int256 x, int256 y) internal pure returns (int256 z) {
        require((z = x + y) >= x == (y >= 0));
    }

    /// @notice Returns x - y, reverts if overflows or underflows
    /// @param x The minuend
    /// @param y The subtrahend
    /// @return z The difference of x and y
    function sub(int256 x, int256 y) internal pure returns (int256 z) {
        require((z = x - y) <= x == (y >= 0));
    }

    function div(uint256 x, uint256 y) internal pure returns(uint256 z){
        require(y > 0);
        z=x/y;
    }
}

contract OwnableData {
    address public owner;
    address public pendingOwner;
}

contract Ownable is OwnableData {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice `owner` defaults to msg.sender on construction.
    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /// @notice Transfers ownership to `newOwner`. Either directly or claimable by the new pending owner.
    /// Can only be invoked by the current `owner`.
    /// @param newOwner Address of the new owner.
    /// @param direct True if `newOwner` should be set immediately. False if `newOwner` needs to use `claimOwnership`.
    /// @param renounce Allows the `newOwner` to be `address(0)` if `direct` and `renounce` is True. Has no effect otherwise.
    function transferOwnership(
        address newOwner,
        bool direct,
        bool renounce
    ) public onlyOwner {
        if (direct) {
            // Checks
            require(newOwner != address(0) || renounce, "Ownable: zero address");

            // Effects
            emit OwnershipTransferred(owner, newOwner);
            owner = newOwner;
            pendingOwner = address(0);
        } else {
            // Effects
            pendingOwner = newOwner;
        }
    }

    /// @notice Needs to be called by `pendingOwner` to claim ownership.
    function claimOwnership() public {
        address _pendingOwner = pendingOwner;

        // Checks
        require(msg.sender == _pendingOwner, "Ownable: caller != pending owner");

        // Effects
        emit OwnershipTransferred(owner, _pendingOwner);
        owner = _pendingOwner;
        pendingOwner = address(0);
    }

    /// @notice Only allows the `owner` to execute the function.
    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not the owner");
        _;
    }

}


interface INodes {
    function walletOfOwner(address _owner) external view returns (uint256[] memory);
    function nodeType(uint256 _nftId) external view returns (uint);
}

contract Sincubator is Ownable {

    using LowGasSafeMath for uint;
    using LowGasSafeMath for uint32;
    uint256 public maxRaise;
    uint256 public totalRaise = 0;
    INodes public Node;
    uint256 public startTimestamp;
    mapping(address => bool) public whitelistedAddresses;
    // Initial tier will be ineligible
    uint256[7] public tierContributions;
    mapping (address => uint256) public contributions;
    mapping (uint => uint) public nodeTypes;
    bool whitelistEnabled = true;
    
    // for skipping node check
    mapping (address => bool) public teamAddresses;

    constructor(address _nodeAddress, uint256 _maxRaise, uint256 _startTimestamp) {
        startTimestamp = _startTimestamp;
        maxRaise = _maxRaise.mul(1e18);     
        Node = INodes(_nodeAddress);
    }


    function addTeamAddresses(address[] calldata _addresses) public onlyOwner {
        for (uint i = 0; i < _addresses.length; i++) {
            teamAddresses[_addresses[i]] = true;
        }
    }

    function whitelistAddresses(address[] calldata users) public onlyOwner {
        for (uint i = 0; i < users.length; i++) {
            whitelistedAddresses[users[i]] = true;
        }
    }
    
    function contribute() public payable {
        if (whitelistEnabled){
            require(whitelistedAddresses[msg.sender], "Not Whitelised!");
        }
        require(block.timestamp >= startTimestamp, "Contributions not open yet!");

        uint256 _maxContribution = maxContribution(msg.sender);
        uint256 _contribution = msg.value;

        require(_contribution == _maxContribution, "Incorrect Amount!");

        require(totalRaise + _contribution <= maxRaise, "Raise Complete!");

        totalRaise += _contribution;
        contributions[msg.sender] += _contribution;
        writeContributionNodeData(msg.sender);
    }

    
    function updateMaxRaise(uint256 _maxRaise) public onlyOwner {
        maxRaise = _maxRaise.mul(1e18);
    }

    function toggleWhitelist(bool _enabled) public onlyOwner {
        whitelistEnabled = _enabled;
    }

    function getBalance() public view returns (uint) {
        return address(this).balance;
    }

    function calculateTier(address wallet) public view returns (uint){
        uint256[] memory nodes = Node.walletOfOwner(wallet);
        uint demonNodes = 0;
        uint maxType = 0;
        uint nodeType;
        for (uint i = 0; i < nodes.length; i++){
            if (nodeTypes[nodes[i]] == 0){
                nodeType = Node.nodeType(nodes[i]);

                //Updating maxType
                if (maxType < nodeType){
                    maxType = nodeType;
                }
                if (nodeType == 5){
                    demonNodes++;
                }
            }
        }

        if (demonNodes >=3){
            return 6;
        }
        
        if (teamAddresses[wallet]){
            return 6;
        }
        return maxType;
    }

    function writeContributionNodeData(address wallet) private returns (bool){
        uint256[] memory nodes = Node.walletOfOwner(wallet);
        uint256 nodeType;
        for (uint i = 0; i < nodes.length; i++){
            if (nodeTypes[nodes[i]] == 0){
                nodeType = Node.nodeType(nodes[i]);
                nodeTypes[nodes[i]] = nodeType;
            }
        }
        return true;

    }

    function updateTierContributions(uint256[7] memory _newTierContributions) public onlyOwner {
        tierContributions = _newTierContributions;
    }

    function maxContribution(address _wallet) public view returns (uint256 amount){
        uint256 tier = calculateTier(_wallet);
        return tierContributions[tier];

    }

    function withdraw() public payable onlyOwner {
        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        require(success);
    }

}
