#!/usr/bin/env python3

import argparse
import sys
from web3 import Web3
from utils import TenexUtils

class TenexCLI:
    def __init__(self):
        self.w3, self.network, self.account, self.hotkey = TenexUtils.get_signer_for_miner()
        self.contract_address = TenexUtils.get_proxy_address(self.network, "tenexiumProtocol")
        self.contract = TenexUtils.get_contract(self.w3, self.network, "tenexiumProtocol")
        pass
    
    def associate(self):
        """Associate the miner with the protocol"""
        try:
            print(f" Associating {self.network}...")
            self.print_before()
            
            # Check current balance
            balance = self.w3.eth.get_balance(self.account.address)
            balance_tao = self.w3.from_wei(balance, 'ether')
            print(f"   Current balance: {balance_tao} TAO")

            # Build transaction
            nonce = self.w3.eth.get_transaction_count(self.account.address)
            gas_price = self.w3.eth.gas_price
            estimated_gas = self.contract.functions.setAssociate(self.hotkey).estimate_gas(
                {
                    'from': self.account.address,
                    'value': 0,
                }
            )

            transaction = self.contract.functions.setAssociate(self.hotkey).build_transaction({
                'from': self.account.address,
                'gas': estimated_gas,
                'gasPrice': gas_price,
                'nonce': nonce,
                'chainId': self.w3.eth.chain_id,
            })

            # Sign and send transaction
            signed_txn = self.w3.eth.account.sign_transaction(transaction, self.account.key)
            tx_hash = self.w3.eth.send_raw_transaction(signed_txn.raw_transaction)
            
            print(f"   Transaction hash: {tx_hash.hex()}")
            print(f"⏳ Waiting for confirmation...")
            
            # Wait for transaction receipt
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
            
            print(f"✅ Associated successfully!")
            print(f"   Block: {receipt.blockNumber}")
            print(f"   Gas used: {receipt.gasUsed}")
        
        except Exception as error:
            print(f"❌ Failed to associate: {error}")
            sys.exit(1)

    def add_liquidity(self, amount: str):
        """Add liquidity to the protocol"""
        try:
            amount_wei = self.w3.to_wei(amount, 'ether')
            
            print(f" Adding {amount} TAO liquidity to {self.network}...")
            self.print_before()
            print(f"   Amount: {amount} TAO ({amount_wei} wei)")
            
            # Check current balance
            balance = self.w3.eth.get_balance(self.account.address)
            balance_tao = self.w3.from_wei(balance, 'ether')
            print(f"   Current balance: {balance_tao} TAO")

            # Check LP info
            lp_info = self.contract.functions.liquidityProviders(self.account.address).call()
            lp_stake = self.w3.from_wei(lp_info[0], 'ether')  # stake is first element
            print(f"   Current LP stake: {lp_stake} TAO")
            
            if balance < amount_wei:
                raise ValueError(f"Insufficient balance. Need {amount} TAO, have {balance_tao} TAO")
            
            # Build transaction
            nonce = self.w3.eth.get_transaction_count(self.account.address)
            gas_price = self.w3.eth.gas_price
            
            estimated_gas = self.contract.functions.addLiquidity().estimate_gas(
                {
                    'from': self.account.address,
                    'value': amount_wei,
                }
            )

            transaction = self.contract.functions.addLiquidity().build_transaction({
                'from': self.account.address,
                'value': amount_wei,
                'gas': estimated_gas,
                'gasPrice': gas_price,
                'nonce': nonce,
                'chainId': self.w3.eth.chain_id,
            })
            
            # Sign and send transaction
            signed_txn = self.w3.eth.account.sign_transaction(transaction, self.account.key)
            tx_hash = self.w3.eth.send_raw_transaction(signed_txn.raw_transaction)
            
            print(f"   Transaction hash: {tx_hash.hex()}")
            print(f"⏳ Waiting for confirmation...")
            
            # Wait for transaction receipt
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
            
            print(f"✅ Liquidity added successfully!")
            print(f"   Block: {receipt.blockNumber}")
            print(f"   Gas used: {receipt.gasUsed}")
            
            # Show updated stats
            self.show_liquidity_stats()
            
        except Exception as error:
            print(f"❌ Failed to add liquidity: {error}")
            sys.exit(1)
    
    def remove_liquidity(self, amount: str):
        """Remove liquidity from the protocol"""
        try:
            amount_wei = self.w3.to_wei(amount, 'ether')
            
            print(f" Removing {amount} TAO liquidity from {self.network}...")
            self.print_before()
            print(f"   Amount: {amount} TAO ({amount_wei} wei)")
            
            # Check LP info
            lp_info = self.contract.functions.liquidityProviders(self.account.address).call()
            lp_stake = self.w3.from_wei(lp_info[0], 'ether')  # stake is first element
            print(f"   Current LP stake: {lp_stake} TAO")
            
            if lp_info[0] < amount_wei:
                raise ValueError(f"Insufficient LP stake. Have {lp_stake} TAO, trying to remove {amount} TAO")
            
            # Build transaction
            nonce = self.w3.eth.get_transaction_count(self.account.address)
            gas_price = self.w3.eth.gas_price
            estimated_gas = self.contract.functions.removeLiquidity(amount_wei).estimate_gas(
                {
                    'from': self.account.address,
                    'value': 0,
                }
            )

            transaction = self.contract.functions.removeLiquidity(amount_wei).build_transaction({
                'from': self.account.address,
                'gas': estimated_gas,
                'gasPrice': gas_price,
                'nonce': nonce,
                'chainId': self.w3.eth.chain_id,
            })
            
            # Sign and send transaction
            signed_txn = self.w3.eth.account.sign_transaction(transaction, self.account.key)
            tx_hash = self.w3.eth.send_raw_transaction(signed_txn.raw_transaction)
            
            print(f"   Transaction hash: {tx_hash.hex()}")
            print(f"⏳ Waiting for confirmation...")
            
            # Wait for transaction receipt
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
            
            print(f"✅ Liquidity removed successfully!")
            print(f"   Block: {receipt.blockNumber}")
            print(f"   Gas used: {receipt.gasUsed}")
            
            # Show updated stats
            self.show_liquidity_stats()
            
        except Exception as error:
            print(f"❌ Failed to remove liquidity: {error}")
            sys.exit(1)
    
    def claim_rewards(self):
        """Claim accrued LP fee rewards"""
        try:
            print(f" Claiming LP fee rewards from {self.network}...")
            self.print_before()
            
            # Check current balance before claiming
            balance_before = self.w3.eth.get_balance(self.account.address)
            balance_tao_before = self.w3.from_wei(balance_before, 'ether')
            print(f"   Balance before: {balance_tao_before} TAO")
            
            # Build transaction
            nonce = self.w3.eth.get_transaction_count(self.account.address)
            gas_price = self.w3.eth.gas_price
            estimated_gas = self.contract.functions.claimLpFeeRewards().estimate_gas(
                {
                    'from': self.account.address,
                    'value': 0,
                }
            )

            transaction = self.contract.functions.claimLpFeeRewards().build_transaction({
                'from': self.account.address,
                'gas': estimated_gas,
                'gasPrice': gas_price,
                'nonce': nonce,
                'chainId': self.w3.eth.chain_id,
            })
            
            # Sign and send transaction
            signed_txn = self.w3.eth.account.sign_transaction(transaction, self.account.key)
            tx_hash = self.w3.eth.send_raw_transaction(signed_txn.raw_transaction)
            
            print(f"   Transaction hash: {tx_hash.hex()}")
            print(f"⏳ Waiting for confirmation...")
            
            # Wait for transaction receipt
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
            
            # Check balance after claiming
            balance_after = self.w3.eth.get_balance(self.account.address)
            balance_tao_after = self.w3.from_wei(balance_after, 'ether')
            claimed_amount = balance_tao_after - balance_tao_before
            
            print(f"✅ Rewards claimed successfully!")
            print(f"   Block: {receipt.blockNumber}")
            print(f"   Gas used: {receipt.gasUsed}")
            print(f"   Claimed amount: {claimed_amount} TAO")
            print(f"   Balance after: {balance_tao_after} TAO")
            
        except Exception as error:
            print(f"❌ Failed to claim rewards: {error}")
            sys.exit(1)

    def show_liquidity_stats(self):
        """Show updated liquidity statistics"""
        try:
            total_lp_stakes = self.w3.from_wei(self.contract.functions.totalLpStakes().call(), 'ether')
            total_lp_fees = self.w3.from_wei(self.contract.functions.totalPendingLpFees().call(), 'ether')
            lp_info = self.contract.functions.liquidityProviders(self.account.address).call()
            liquidity_circuit_breaker = self.contract.functions.liquidityCircuitBreaker().call()
            
            print(f"\n📊 Updated Protocol Stats:")
            print(f"   Total LP Stakes: {total_lp_stakes} TAO")  # totalLpStakesAmount
            print(f"   Total PendingLP Fees: {total_lp_fees} TAO")   # totalLpFeesAmount
            print(f"   Liquidity Circuit Breaker: {liquidity_circuit_breaker}")
            
            print(f"\n👤 Your LP Info:")
            print(f"   LP Stake: {self.w3.from_wei(lp_info[0], 'ether')} TAO")
            print(f"   LP Shares: {self.w3.from_wei(lp_info[3], 'ether')}")
            print(f"   Is Active: {lp_info[5]}")
            
        except Exception as error:
            print(f"⚠️  Could not fetch updated stats: {error}")

    def show_position_stats(self, position_id: int):
        """Show position statistics"""
        try:
            # Get position data from contract
            position_data = self.contract.functions.positions(self.account.address, position_id).call()
            
            # Unpack position data
            alpha_netuid = position_data[0]
            initial_collateral = position_data[1]
            added_collateral = position_data[2]
            borrowed = position_data[3]
            alpha_amount = position_data[4]
            leverage = position_data[5]
            entry_price = position_data[6]
            validator_hotkey = position_data[9]
            is_active = position_data[10]
            
            # Convert wei to TAO
            initial_collateral_tao = self.w3.from_wei(initial_collateral, 'ether')
            added_collateral_tao = self.w3.from_wei(added_collateral, 'ether')
            borrowed_tao = self.w3.from_wei(borrowed, 'ether')
            alpha_amount_tao = self.w3.from_wei(alpha_amount, 'gwei')
            entry_price_tao = self.w3.from_wei(entry_price, 'ether')

            # Convert leverage from scaled format
            leverage_actual = leverage / 1e9  # Convert from PRECISION format
            
            # Calculate total collateral
            total_collateral_tao = initial_collateral_tao + added_collateral_tao
            
            print(f"\n📊 Position #{position_id} Statistics:")
            print(f"   Status: {'🟢 Active' if is_active else '🔴 Inactive'}")
            print(f"   Alpha Netuid: {alpha_netuid}")
            print(f"   Validator Hotkey: {validator_hotkey.hex()}")
            
            print(f"\n💰 Collateral & Borrowing:")
            print(f"   Initial Collateral: {initial_collateral_tao} TAO")
            print(f"   Added Collateral: {added_collateral_tao} TAO")
            print(f"   Total Collateral: {total_collateral_tao} TAO")
            print(f"   Borrowed Amount: {borrowed_tao} TAO")
            print(f"   Leverage: {leverage_actual}x")
            
            print(f"\n🪙 Alpha Holdings:")
            print(f"   Alpha Amount: {alpha_amount_tao} TAO")
            print(f"   Entry Price: {entry_price_tao} TAO per Alpha")
            
        except Exception as error:
            print(f"❌ Failed to fetch position stats: {error}")
            print(f"   Position ID: {position_id}")
            print(f"   User: {self.account.address}")
            print(f"   Make sure the position exists and is active.")
    
    def open_position(self, netuid: int, leverage: float, max_slippage: float, collateral_amount: str):
        """Open a leveraged position"""
        try:
            amount_wei = self.w3.to_wei(collateral_amount, 'ether')
            leverage_scaled = int(leverage * 1e9)  # Scale leverage to match contract precision
            max_slippage_bps = int(max_slippage * 100)  # Convert to basis points
            
            print(f" Opening leveraged position on {self.network}...")
            self.print_before()
            print(f"   Netuid: {netuid}")
            print(f"   Leverage: {leverage}x")
            print(f"   Max Slippage: {max_slippage}% ({max_slippage_bps} bps)")
            print(f"   Collateral: {collateral_amount} TAO ({amount_wei} wei)")
            
            # Check current balance
            balance = self.w3.eth.get_balance(self.account.address)
            balance_tao = self.w3.from_wei(balance, 'ether')
            print(f"   Current balance: {balance_tao} TAO")
            
            if balance < amount_wei:
                raise ValueError(f"Insufficient balance. Need {collateral_amount} TAO, have {balance_tao} TAO")
            
            # Build transaction
            nonce = self.w3.eth.get_transaction_count(self.account.address)
            gas_price = self.w3.eth.gas_price
            estimated_gas = self.contract.functions.openPosition(netuid, leverage_scaled, max_slippage_bps).estimate_gas(
                {
                    'from': self.account.address,
                    'value': amount_wei,
                }
            )

            transaction = self.contract.functions.openPosition(netuid, leverage_scaled, max_slippage_bps).build_transaction({
                'from': self.account.address,
                'value': amount_wei,
                'gas': estimated_gas,
                'gasPrice': gas_price,
                'nonce': nonce,
                'chainId': self.w3.eth.chain_id,
            })
            
            # Sign and send transaction
            signed_txn = self.w3.eth.account.sign_transaction(transaction, self.account.key)
            tx_hash = self.w3.eth.send_raw_transaction(signed_txn.raw_transaction)
            
            print(f"   Transaction hash: {tx_hash.hex()}")
            print(f"⏳ Waiting for confirmation...")
            
            # Wait for transaction receipt
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
            
            print(f"✅ Position opened successfully!")
            print(f"   Block: {receipt.blockNumber}")
            print(f"   Gas used: {receipt.gasUsed}")
            
            # Show position stats after opening
            # Get the position ID from the transaction logs or use nextPositionId
            try:
                # Try to get the next position ID that would have been assigned
                next_position_id = self.contract.functions.nextPositionId(self.account.address).call()
                position_id = next_position_id - 1  # The position that was just created
                print(f"\n📊 New Position Created:")
                self.show_position_stats(position_id)
            except Exception as e:
                print(f"⚠️  Could not fetch new position stats: {e}")
            
        except Exception as error:
            print(f"❌ Failed to open position: {error}")
            sys.exit(1)

    def close_position(self, position_id: int, amount_to_close: str, max_slippage: float, full_close: bool = False):
        """Close a position"""
        try:
            if full_close:
                amount_gwei = 0  # 0 means close the entire position
                amount_display = "ENTIRE POSITION"
            else:
                amount_gwei = self.w3.to_wei(amount_to_close, 'gwei')
                amount_display = f"{amount_to_close} Alpha"
            
            max_slippage_bps = int(max_slippage * 100)  # Convert to basis points
            
            print(f" Closing position {position_id} on {self.network}...")
            self.print_before()
            print(f"   Position ID: {position_id}")
            print(f"   Amount to close: {amount_display}")
            print(f"   Max Slippage: {max_slippage}% ({max_slippage_bps} bps)")
            
            # Build transaction
            nonce = self.w3.eth.get_transaction_count(self.account.address)
            gas_price = self.w3.eth.gas_price
            estimated_gas = self.contract.functions.closePosition(position_id, amount_gwei, max_slippage_bps).estimate_gas(
                {
                    'from': self.account.address,
                    'value': 0,
                }
            )

            transaction = self.contract.functions.closePosition(position_id, amount_gwei, max_slippage_bps).build_transaction({
                'from': self.account.address,
                'gas': estimated_gas,
                'gasPrice': gas_price,
                'nonce': nonce,
                'chainId': self.w3.eth.chain_id,
            })
            
            # Sign and send transaction
            signed_txn = self.w3.eth.account.sign_transaction(transaction, self.account.key)
            tx_hash = self.w3.eth.send_raw_transaction(signed_txn.raw_transaction)
            
            print(f"   Transaction hash: {tx_hash.hex()}")
            print(f"⏳ Waiting for confirmation...")
            
            # Wait for transaction receipt
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
            
            print(f"✅ Position closed successfully!")
            print(f"   Block: {receipt.blockNumber}")
            print(f"   Gas used: {receipt.gasUsed}")
            
            # Show updated position stats after closing
            try:
                print(f"\n📊 Updated Position Stats:")
                self.show_position_stats(position_id)
            except Exception as e:
                print(f"⚠️  Could not fetch updated position stats: {e}")
            
        except Exception as error:
            print(f"❌ Failed to close position: {error}")
            sys.exit(1)

    def add_collateral(self, position_id: int, collateral_amount: str):
        """Add collateral to an existing position"""
        try:
            amount_wei = self.w3.to_wei(collateral_amount, 'ether')
            
            print(f" Adding {collateral_amount} TAO collateral to position {position_id} on {self.network}...")
            self.print_before()
            print(f"   Position ID: {position_id}")
            print(f"   Collateral amount: {collateral_amount} TAO ({amount_wei} wei)")
            
            # Check current balance
            balance = self.w3.eth.get_balance(self.account.address)
            balance_tao = self.w3.from_wei(balance, 'ether')
            print(f"   Current balance: {balance_tao} TAO")
            
            if balance < amount_wei:
                raise ValueError(f"Insufficient balance. Need {collateral_amount} TAO, have {balance_tao} TAO")
            
            # Build transaction
            nonce = self.w3.eth.get_transaction_count(self.account.address)
            gas_price = self.w3.eth.gas_price
            estimated_gas = self.contract.functions.addCollateral(position_id).estimate_gas(
                {
                    'from': self.account.address,
                    'value': amount_wei,
                }
            )

            transaction = self.contract.functions.addCollateral(position_id).build_transaction({
                'from': self.account.address,
                'value': amount_wei,
                'gas': estimated_gas,
                'gasPrice': gas_price,
                'nonce': nonce,
                'chainId': self.w3.eth.chain_id,
            })
            
            # Sign and send transaction
            signed_txn = self.w3.eth.account.sign_transaction(transaction, self.account.key)
            tx_hash = self.w3.eth.send_raw_transaction(signed_txn.raw_transaction)
            
            print(f"   Transaction hash: {tx_hash.hex()}")
            print(f"⏳ Waiting for confirmation...")
            
            # Wait for transaction receipt
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
            
            print(f"✅ Collateral added successfully!")
            print(f"   Block: {receipt.blockNumber}")
            print(f"   Gas used: {receipt.gasUsed}")
            
            # Show updated position stats after adding collateral
            try:
                print(f"\n📊 Updated Position Stats:")
                self.show_position_stats(position_id)
            except Exception as e:
                print(f"⚠️  Could not fetch updated position stats: {e}")
            
        except Exception as error:
            print(f"❌ Failed to add collateral: {error}")
            sys.exit(1)

    def print_before(self):
        """Print transaction details"""
        print(f"📝 Transaction details:")
        print(f"   Network: {self.network}")
        if self.hotkey:
            print(f"   Hotkey: {self.hotkey}")
        print(f"   From: {self.account.address}")
        print(f"   To: {self.contract_address}")
        
        
def validate_amount(amount: str):
    try:
        amount = float(amount)
        if amount <= 0:
            raise ValueError("Amount must be positive")
    except ValueError as e:
        print(f"❌ Invalid amount: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(
        description="Tenex CLI - Liquidity Management Tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 tenex.py associate
  python3 tenex.py addliq --amount <amount>
  python3 tenex.py removeliq --amount <amount>
  python3 tenex.py claim
  python3 tenex.py showstats
  python3 tenex.py showpos --position-id <id>
  python3 tenex.py openpos --netuid <netuid> --leverage <leverage> --max-slippage <slippage> --collateral <amount>
  python3 tenex.py closepos --position-id <id> --amount <amount> --max-slippage <slippage>
  python3 tenex.py closepos --position-id <id> --full --max-slippage <slippage>
  python3 tenex.py addcollateral --position-id <id> --amount <amount>
        """
    )
    
    parser.add_argument(
        "command",
        choices=["associate", "addliq", "removeliq", "claim", "showstats", "showpos", "openpos", "closepos", "addcollateral"],
        help="Command to execute"
    )
    
    parser.add_argument(
        "--amount",
        required=False,
        help="Amount of TAO to add/remove"
    )
    
    parser.add_argument(
        "--netuid",
        type=int,
        help="Subnet ID for position operations"
    )
    
    parser.add_argument(
        "--leverage",
        type=float,
        help="Leverage multiplier (e.g., 2.5 for 2.5x leverage)"
    )
    
    parser.add_argument(
        "--max-slippage",
        type=float,
        help="Maximum acceptable slippage in percentage (e.g., 1.0 for 1%)"
    )
    
    parser.add_argument(
        "--collateral",
        help="Collateral amount in TAO"
    )
    
    parser.add_argument(
        "--position-id",
        type=int,
        help="Position ID for close/add collateral operations"
    )
    
    parser.add_argument(
        "--full",
        action="store_true",
        help="Close the entire position (for closepos command)"
    )
    
    parser.add_argument(
        "--network",
        default="mainnet",
        choices=["testnet", "mainnet"],
        help="Network to use (default: mainnet)"
    )
    
    args = parser.parse_args()
    
    cli = TenexCLI()
    
    if args.command == "associate":
        cli.associate()
    elif args.command == "addliq":
        validate_amount(args.amount)
        cli.add_liquidity(args.amount)
    elif args.command == "removeliq":
        validate_amount(args.amount)
        cli.remove_liquidity(args.amount)
    elif args.command == "claim":
        cli.claim_rewards()
    elif args.command == "showstats":
        cli.show_liquidity_stats()
    elif args.command == "showpos":
        if not args.position_id:
            print("❌ showpos requires --position-id")
            sys.exit(1)
        cli.show_position_stats(args.position_id)
    elif args.command == "openpos":
        if not args.netuid or not args.leverage or not args.max_slippage or not args.collateral:
            print("❌ openpos requires --netuid, --leverage, --max-slippage, and --collateral")
            sys.exit(1)
        validate_amount(args.collateral)
        cli.open_position(args.netuid, args.leverage, args.max_slippage, args.collateral)
    elif args.command == "closepos":
        if not args.position_id or not args.max_slippage:
            print("❌ closepos requires --position-id and --max-slippage")
            sys.exit(1)
        
        if args.full:
            # Full close - no amount validation needed
            cli.close_position(args.position_id, "0", args.max_slippage, full_close=True)
        else:
            # Partial close - amount is required
            if not args.amount:
                print("❌ closepos requires --amount (or use --full to close entire position)")
                sys.exit(1)
            validate_amount(args.amount)
            cli.close_position(args.position_id, args.amount, args.max_slippage, full_close=False)
    elif args.command == "addcollateral":
        if not args.position_id or not args.amount:
            print("❌ addcollateral requires --position-id and --amount")
            sys.exit(1)
        validate_amount(args.amount)
        cli.add_collateral(args.position_id, args.amount)

if __name__ == "__main__":
    main()
