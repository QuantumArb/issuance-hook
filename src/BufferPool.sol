pragma solidity ^0.8.0;
<<<<<<< Updated upstream
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPyth} from "pyth-sdk-solidity/contracts/interfaces/IPyth.sol";
import {PythStructs} from "pyth-sdk-solidity/contracts/libraries/PythStructs.sol";

contract BufferPool is Ownable {
    using SafeERC20 for IERC20;

    error HookNotSet();
    error InvalidAmount();
    error ZeroAddress();

    struct Hook {
        IERC20 paymentToken;
        IERC20 issuanceToken;
        bytes32 paymentTokenOracle;
        bytes32 issuanceTokenOracle;
    }

    mapping(address => Hook) public hooks;
    
    IPyth public immutable pyth;

    constructor(IPyth _pyth) Ownable(msg.sender) {
        if (address(_pyth) == address(0)) revert ZeroAddress();
        pyth = _pyth;
    }

    function issue(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();

        Hook memory hook = hooks[msg.sender];
        _validateHook(hook);

        hook.paymentToken.safeTransferFrom(msg.sender, address(this), amount);
        
    }

    function previewIssuance(uint256 amount) public view returns (uint256) {
        Hook memory hook = hooks[msg.sender];
        _validateHook(hook);

        return hook.issuanceToken.previewMint(amount);
    }

    function setHook(address _paymentToken, address _issuanceToken, address _hook) external onlyOwner {
        if (_paymentToken == address(0) || _issuanceToken == address(0) || _hook == address(0)) revert ZeroAddress();
        hooks[_hook] = Hook(IERC20(_paymentToken), IERC20(_issuanceToken));
    }

    function _getPrice(bytes32 priceId) internal view returns (uint256) {

    function _validateHook(Hook memory hook) internal view {
        if (address(hook.paymentToken) == address(0) || address(hook.issuanceToken) == address(0)) revert HookNotSet();
    }
}
=======
import {Ownable} from "lib/v4-core/lib/forge-std/src/auth/Ownable.sol";

contract BufferPool is onlyOwner {
    struct Hook {
        address paymentToken;
        address issuanceToken;
    }
    
    mapping(address => Hook) public hooks;

    function addHook(address _paymentToken, address _issuanceToken, address _hook) external {
        hooks[_hook] = Hook(_paymentToken, _issuanceToken);
    }


}
>>>>>>> Stashed changes
