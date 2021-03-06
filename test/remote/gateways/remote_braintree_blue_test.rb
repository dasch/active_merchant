require 'test_helper'

class RemoteBraintreeBlueTest < Test::Unit::TestCase
  def setup
    @gateway = BraintreeGateway.new(fixtures(:braintree_blue))

    @amount = 100
    @declined_amount = 2000_00
    @credit_card = credit_card('5105105105105100')
    @declined_card = credit_card('4000300011112220')

    @options = {
      :order_id => '1',
      :billing_address => address(:country => "United States of America"),
      :description => 'Store Purchase'
    }
  end

  def test_successful_authorize
    assert response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response
    assert_equal '1000 Approved', response.message
    assert_equal 'authorized', response.params["braintree_transaction"]["status"]
  end

  def test_successful_authorize_with_order_id
    assert response = @gateway.authorize(@amount, @credit_card, :order_id => '123')
    assert_success response
    assert_equal '1000 Approved', response.message
    assert_equal '123', response.params["braintree_transaction"]["order_id"]
  end

  def test_successful_purchase_using_vault_id
    assert response = @gateway.store(@credit_card)
    assert_success response
    assert_equal 'OK', response.message
    customer_vault_id = response.params["customer_vault_id"]
    assert_match /\A\d{6,7}\z/, customer_vault_id

    assert response = @gateway.purchase(@amount, customer_vault_id)
    assert_success response
    assert_equal '1000 Approved', response.message
    assert_equal 'submitted_for_settlement', response.params["braintree_transaction"]["status"]
    assert_equal customer_vault_id, response.params["braintree_transaction"]["customer_details"]["id"]
  end

  def test_successful_purchase_using_vault_id_as_integer
    assert response = @gateway.store(@credit_card)
    assert_success response
    assert_equal 'OK', response.message
    customer_vault_id = response.params["customer_vault_id"]
    assert_match /\A\d{6,7}\z/, customer_vault_id

    assert response = @gateway.purchase(@amount, customer_vault_id.to_i)
    assert_success response
    assert_equal '1000 Approved', response.message
    assert_equal 'submitted_for_settlement', response.params["braintree_transaction"]["status"]
    assert_equal customer_vault_id, response.params["braintree_transaction"]["customer_details"]["id"]
  end


  def test_successful_purchase
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal '1000 Approved', response.message
    assert_equal 'submitted_for_settlement', response.params["braintree_transaction"]["status"]
  end

  def test_avs_match
    assert response = @gateway.purchase(@amount, @credit_card,
      @options.merge(
        :billing_address => {:address1 => "1 E Main St", :zip => "60622"}
      )
    )
    assert_success response
    assert_equal({'code' => nil, 'message' => nil, 'street_match' => 'M', 'postal_match' => 'M'}, response.avs_result)
  end

  def test_avs_no_match
    assert response = @gateway.purchase(@amount, @credit_card,
      @options.merge(
        :billing_address => {:address1 => "200 E Main St", :zip => "20000"}
      )
    )
    assert_success response
    assert_equal({'code' => nil, 'message' => nil, 'street_match' => 'N', 'postal_match' => 'N'}, response.avs_result)
  end

  def test_cvv_match
    assert response = @gateway.purchase(@amount, credit_card('5105105105105100', :verification_value => '400'))
    assert_success response
    assert_equal({'code' => 'M', 'message' => ''}, response.cvv_result)
  end

  def test_cvv_no_match
    assert response = @gateway.purchase(@amount, credit_card('5105105105105100', :verification_value => '200'))
    assert_success response
    assert_equal({'code' => 'N', 'message' => ''}, response.cvv_result)
  end

  def test_successful_purchase_with_email
    assert response = @gateway.purchase(@amount, @credit_card,
      :email => "customer@example.com"
    )
    assert_success response
    transaction = response.params["braintree_transaction"]
    assert_equal 'customer@example.com', transaction["customer_details"]["email"]
  end

  def test_purchase_with_store_using_random_customer_id
    assert response = @gateway.purchase(
      @amount, credit_card('5105105105105100'), @options.merge(:store => true)
    )
    assert_success response
    assert_equal '1000 Approved', response.message
    assert_match /\A\d{6,7}\z/, response.params["customer_vault_id"]
    assert_equal '510510', response.params["braintree_transaction"]["vault_customer"]["credit_cards"][0]["bin"]
    assert_equal '510510', Braintree::Customer.find(response.params["customer_vault_id"]).credit_cards[0].bin
  end

  def test_purchase_with_store_using_specified_customer_id
    customer_id = rand(1_000_000_000).to_s
    assert response = @gateway.purchase(
      @amount, credit_card('5105105105105100'), @options.merge(:store => customer_id)
    )
    assert_success response
    assert_equal '1000 Approved', response.message
    assert_equal customer_id, response.params["customer_vault_id"]
    assert_equal '510510', response.params["braintree_transaction"]["vault_customer"]["credit_cards"][0]["bin"]
    assert_equal '510510', Braintree::Customer.find(response.params["customer_vault_id"]).credit_cards[0].bin
  end

  def test_successful_purchase_with_addresses
    billing_address = {
      :address1 => '1 E Main St',
      :address2 => 'Suite 101',
      :company => 'Widgets Co',
      :city => 'Chicago',
      :state => 'IL',
      :zip => '60622',
      :country => 'United States of America'
    }
    shipping_address = {
      :address1 => '1 W Main St',
      :address2 => 'Suite 102',
      :company => 'Widgets Company',
      :city => 'Bartlett',
      :state => 'Illinois',
      :zip => '60103',
      :country => 'Mexico'
    }
    assert response = @gateway.purchase(@amount, @credit_card,
      :billing_address => billing_address,
      :shipping_address => shipping_address
    )
    assert_success response
    transaction = response.params["braintree_transaction"]
    assert_equal '1 E Main St', transaction["billing_details"]["street_address"]
    assert_equal 'Suite 101', transaction["billing_details"]["extended_address"]
    assert_equal 'Widgets Co', transaction["billing_details"]["company"]
    assert_equal 'Chicago', transaction["billing_details"]["locality"]
    assert_equal 'IL', transaction["billing_details"]["region"]
    assert_equal '60622', transaction["billing_details"]["postal_code"]
    assert_equal 'United States of America', transaction["billing_details"]["country_name"]
    assert_equal '1 W Main St', transaction["shipping_details"]["street_address"]
    assert_equal 'Suite 102', transaction["shipping_details"]["extended_address"]
    assert_equal 'Widgets Company', transaction["shipping_details"]["company"]
    assert_equal 'Bartlett', transaction["shipping_details"]["locality"]
    assert_equal 'Illinois', transaction["shipping_details"]["region"]
    assert_equal '60103', transaction["shipping_details"]["postal_code"]
    assert_equal 'Mexico', transaction["shipping_details"]["country_name"]
  end

  def test_unsuccessful_purchase_declined
    assert response = @gateway.purchase(@declined_amount, @credit_card, @options)
    assert_failure response
    assert_equal '2000 Do Not Honor', response.message
  end

  def test_unsuccessful_purchase_validation_error
    assert response = @gateway.purchase(@amount, @credit_card,
      @options.merge(:email => "invalid_email")
    )
    assert_failure response
    assert_equal 'Email is an invalid format. (81604)', response.message
    assert_equal nil, response.params["braintree_transaction"]
  end

  def test_authorize_and_capture
    amount = @amount
    assert auth = @gateway.authorize(amount, @credit_card, @options)
    assert_success auth
    assert_equal '1000 Approved', auth.message
    assert auth.authorization
    assert capture = @gateway.capture(amount, auth.authorization)
    assert_success capture
  end

  def test_authorize_and_void
    amount = @amount
    assert auth = @gateway.authorize(amount, @credit_card, @options)
    assert_success auth
    assert_equal '1000 Approved', auth.message
    assert auth.authorization
    assert void = @gateway.void(auth.authorization)
    assert_success void
    assert_equal 'voided', void.params["braintree_transaction"]["status"]
  end

  def test_failed_void
    amount = @amount
    assert auth = @gateway.authorize(amount, @credit_card, @options)
    assert_success auth
    assert_equal '1000 Approved', auth.message
    assert auth.authorization
    assert void = @gateway.void(auth.authorization)
    assert_success void
    assert_equal 'voided', void.params["braintree_transaction"]["status"]
    assert failed_void = @gateway.void(auth.authorization)
    assert_failure failed_void
    assert_equal 'Transaction can only be voided if status is authorized or submitted_for_settlement. (91504)', failed_void.message
    assert_equal nil, failed_void.params["braintree_transaction"]
  end

  def test_failed_capture_with_invalid_transaction_id
    assert response = @gateway.capture(@amount, 'invalidtransactionid')
    assert_failure response
    assert_equal 'Braintree::NotFoundError', response.message
  end

  def test_invalid_login
    gateway = BraintreeBlueGateway.new(:merchant_id => "invalid", :public_key => "invalid", :private_key => "invalid")
    assert response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'Braintree::AuthenticationError', response.message
  end

  def test_successful_add_to_vault_with_store_method
    assert response = @gateway.store(@credit_card)
    assert_success response
    assert_equal 'OK', response.message
    assert_match /\A\d{6,7}\z/, response.params["customer_vault_id"]
  end

  def test_failed_add_to_vault
    assert response = @gateway.store(credit_card('5105105105105101'))
    assert_failure response
    assert_equal 'Credit card number is invalid. (81715)', response.message
    assert_equal nil, response.params["braintree_customer"]
    assert_equal nil, response.params["customer_vault_id"]
  end

  def test_unstore
    assert response = @gateway.store(@credit_card)
    assert_success response
    assert_equal 'OK', response.message
    assert customer_vault_id = response.params["customer_vault_id"]
    assert delete_response = @gateway.unstore(customer_vault_id)
    assert_success delete_response
  end

  def test_unstore_with_delete_method
    assert response = @gateway.store(@credit_card)
    assert_success response
    assert_equal 'OK', response.message
    assert customer_vault_id = response.params["customer_vault_id"]
    assert delete_response = @gateway.delete(customer_vault_id)
    assert_success delete_response
  end

  def test_successful_credit
    assert response = @gateway.credit(@amount, @credit_card, @options)
    assert_success response
    assert_equal '1002 Processed', response.message
    assert_equal 'submitted_for_settlement', response.params["braintree_transaction"]["status"]
  end

  def test_failed_credit
    assert response = @gateway.credit(@amount, credit_card('5105105105105101'), @options)
    assert_failure response
    assert_equal 'Credit card number is invalid. (81715)', response.message
  end

  def test_successful_update
    assert response = @gateway.store(
      credit_card('4111111111111111',
        :first_name => 'Old First', :last_name => 'Old Last',
        :month => 9, :year => 2012
      ),
      :email => "old@example.com"
    )
    assert_success response
    assert_equal 'OK', response.message
    customer_vault_id = response.params["customer_vault_id"]
    assert_match /\A\d{6,7}\z/, customer_vault_id
    assert_equal "old@example.com", response.params["braintree_customer"]["email"]
    assert_equal "Old First", response.params["braintree_customer"]["first_name"]
    assert_equal "Old Last", response.params["braintree_customer"]["last_name"]
    assert_equal "411111", response.params["braintree_customer"]["credit_cards"][0]["bin"]
    assert_equal "09/2012", response.params["braintree_customer"]["credit_cards"][0]["expiration_date"]

    assert response = @gateway.update(
      customer_vault_id,
      credit_card('5105105105105100',
        :first_name => 'New First', :last_name => 'New Last',
        :month => 10, :year => 2014
      ),
      :email => "new@example.com"
    )
    assert_success response
    assert_equal "new@example.com", response.params["braintree_customer"]["email"]
    assert_equal "New First", response.params["braintree_customer"]["first_name"]
    assert_equal "New Last", response.params["braintree_customer"]["last_name"]
    assert_equal "510510", response.params["braintree_customer"]["credit_cards"][0]["bin"]
    assert_equal "10/2014", response.params["braintree_customer"]["credit_cards"][0]["expiration_date"]
  end

  def test_failed_customer_update
    assert response = @gateway.store(credit_card('4111111111111111'), :email => "email@example.com")
    assert_success response
    assert_equal 'OK', response.message
    assert customer_vault_id = response.params["customer_vault_id"]

    assert response = @gateway.update(
      customer_vault_id,
      credit_card('5105105105105100'),
      :email => "invalid-email"
    )
    assert_failure response
    assert_equal 'Email is an invalid format. (81604)', response.message
    assert_equal nil, response.params["braintree_customer"]
    assert_equal nil, response.params["customer_vault_id"]
  end

  def test_failed_customer_update_invalid_vault_id
    assert response = @gateway.update('invalid-customer-id', credit_card('5105105105105100'))
    assert_failure response
    assert_equal 'Braintree::NotFoundError', response.message
  end

  def test_failed_credit_card_update
    assert response = @gateway.store(credit_card('4111111111111111'))
    assert_success response
    assert_equal 'OK', response.message
    assert customer_vault_id = response.params["customer_vault_id"]

    assert response = @gateway.update(
      customer_vault_id,
      credit_card('5105105105105101')
    )
    assert_failure response
    assert_equal 'Credit card number is invalid. (81715)', response.message
  end

  def test_customer_does_not_have_credit_card_failed_update
    customer_without_credit_card = Braintree::Customer.create!
    assert response = @gateway.update(customer_without_credit_card.id, credit_card('5105105105105100'))
    assert_failure response
    assert_equal 'Braintree::NotFoundError', response.message
  end
end
