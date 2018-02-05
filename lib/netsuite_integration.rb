# frozen_string_literal: true

$LOAD_PATH.unshift File.dirname(__FILE__)

require 'netsuite'

require 'netsuite_integration/services/base'
require 'netsuite_integration/services/inventory_item'
require 'netsuite_integration/services/non_inventory_item_service'
require 'netsuite_integration/services/country_service'
require 'netsuite_integration/services/state_service'
require 'netsuite_integration/services/vendor'

require 'netsuite_integration/base'
require 'netsuite_integration/product'
require 'netsuite_integration/purchase_order'
require 'netsuite_integration/vendor'
require 'netsuite_integration/inventory_adjustment'
require 'netsuite_integration/maintain_inventory_item'
require 'netsuite_integration/gl_journal'
require 'netsuite_integration/gl_rules'
require 'netsuite_integration/maintain_supplier'
require 'netsuite_integration/vendor_bill'