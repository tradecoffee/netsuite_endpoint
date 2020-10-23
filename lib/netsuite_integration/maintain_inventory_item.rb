# frozen_string_literal: true

module NetsuiteIntegration
  class MaintainInventoryItem < Base
    attr_reader :config, :payload, :ns_inventoryitem, :inventoryitem_payload

    def initialize(config, payload = {})
      super(config, payload)
      @config = config

      @inventoryitem_payload = payload[:product]

      inventoryitem_payload['sku'].map do |line_item|
        add_sku(line_item)
      end
    end

    # exit if no changes limit the amount of nestuite calls/changes
    def sku_needs_upd(line_item)
      ref = ExternalReference.products.find_by_external_id(solidus_id: line_item['id'].to_i)
                             .try!(:object)
      if ref.nil? ||
         ref['netsuite'].nil? ||
         ref['netsuite']['sku'] != line_item['sku'] ||
         ref['netsuite']['description'] != line_item['name'] ||
         ref['netsuite']['cost']&.to_f != line_item['cost'].to_f
        true
      else false
      end
    end

    def add_sku(line_item)
      # exit out prevent netsuite calls as it .... they are to expensive!
      return unless sku_needs_upd(line_item)

      sku = line_item['sku']
      taxschedule = line_item['tax_type']
      dropship_account = line_item['dropship_account']
      description = line_item['name'].rstrip
      stock_desc = description.rstrip[0, 21]
      ns_id = line_item['ns_id']
      cost = line_item['cost'].to_f

      # always find sku using internal id incase of sku rename
      item = if !ns_id.nil?
               inventory_item_service.find_noninventoryitem_by_internal_id(ns_id)
             else
               inventory_item_service.find_noninventoryitem_by_id(sku)
             end

      if !item.present?
        item = NetSuite::Records::NonInventoryResaleItem.new(
          item_id: sku,
          tax_schedule: { internal_id: taxschedule },
          expense_account: { internal_id: dropship_account },
          upc_code: sku,
          vendor_name: description[0, 60],
          purchase_description: description,
          stock_description: stock_desc,
          cost: cost
        )
        item.add
      elsif
            item.present? &&
            (stock_desc != item.stock_description || sku != item.item_id || ns_id != item.internal_id || cost != item.cost.to_f)

        item.update(
          item_id: sku,
          tax_schedule: { internal_id: taxschedule },
          expense_account: { internal_id: dropship_account },
          upc_code: sku,
          vendor_name: description[0, 60],
          purchase_description: description,
          sales_description: description,
          stock_description: stock_desc,
          cost: cost
        )
      end

      if item.errors.present? { |e| e.type != 'WARN' }
        raise "Item Update/create failed: #{item.errors.map(&:message)}"
      else
        line_item = { sku: sku, netsuite_id: item.internal_id,
                      description: description, cost: cost }
        ExternalReference.record :product, sku, { netsuite: line_item },
                                 netsuite_id: item.internal_id
      end
    end

    def inventory_item_service
      @inventory_item_service ||= NetsuiteIntegration::Services::InventoryItem
                                  .new(@config)
    end
  end
end
