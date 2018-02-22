module NetsuiteIntegration
  class MaintainInventoryItem < Base
    attr_reader :config, :payload, :ns_inventoryitem, :inventoryitem_payload

    def initialize(config, payload = {})
      super(config, payload)
      @config = config

      @inventoryitem_payload = payload[:product]

      # awlays keep external_id in numeric format
      ext_id = if sku.is_a? Numeric
                 sku.to_i
               else
                 sku
               end

      # always find sku using internal id incase of sku rename
      existing =  if !ns_id.nil?
                    inventory_item_service.find_by_internal_id(ns_id)
                  else
                    inventory_item_service.find_by_item_id(sku)
                  end

      item = if existing.present?
               # if expense account is blank then its an inventory item
                  if expense_sku? && item.record_type.include?('InventoryItem')
                      raise 'Item Update/create failed , inventory type mismatch fix in Netsuite'
                  end
              end

      if !item.present?
        item = if expense_sku?
                 NetSuite::Records::NonInventoryResaleItem.new(
                   item_id: sku,
                   external_id: ext_id,
                   tax_schedule: { internal_id: taxschedule },
                   expense_account: { internal_id: dropship_account },
                   upc_code: sku,
                   vendor_name: description[0, 60],
                   purchase_description: description,
                   stock_description: description[0, 21]
                 )
               else
                 NetSuite::Records::InventoryItem.new(
                   item_id: sku,
                   external_id: ext_id,
                   tax_schedule: { internal_id: taxschedule },
                   upc_code: sku,
                   vendor_name: description[0, 60],
                   purchase_description: description,
                   stock_description: description[0, 21]
                 )
               end
        item.add
      elsif item.record_type.include?('NonInventorySaleItem')
            item.update(
              item_id: sku,
              external_id: ext_id,
              tax_schedule: { internal_id: taxschedule },
              expense_account: { internal_id: dropship_account },
              upc_code: sku,
              vendor_name: description[0, 60],
              purchase_description: description,
              stock_description: description[0, 21]
            )
      elsif item.record_type.include?('InventoryItem')
            item.update(
              item_id: sku,
              external_id: ext_id,
              tax_schedule: { internal_id: taxschedule },
              upc_code: sku,
              vendor_name: description[0, 60],
              purchase_description: description,
              stock_description: description[0, 21]
            )
      end

      if item.errors.any? { |e| e.type != 'WARN' }
        raise "Item Update/create failed: #{item.errors.map(&:message)}"
      else
        line_item = { sku: sku, netsuite_id: item.internal_id,
                      description: description }
        ExternalReference.record :product, sku, { netsuite: line_item },
                                 netsuite_id: item.internal_id
      end
    end

    def sku
        inventoryitem_payload['sku']
    end

    def expense_sku?
		    inventoryitem_payload['sku_type']=='expense'
    end

    def taxschedule
        inventoryitem_payload['tax_type']
    end

    def dropship_account
        inventoryitem_payload['dropship_account']
    end

    def description
        inventoryitem_payload['name']
    end

    def ns_id
     inventoryitem_payload['ns_id']
    end

    def inventory_item_service
      @inventory_item_service ||= NetsuiteIntegration::Services::InventoryItem
                                  .new(@config)
    end

  end
end
