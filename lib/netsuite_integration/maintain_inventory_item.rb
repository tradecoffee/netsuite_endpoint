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
                    find_noninvitem_by_id(ns_id) || find_invitem_by_id(ns_id)
                  else
                    inventory_item_service.find_by_item_id(sku)
                  end

      item = if existing.present?
               # if expense account is blank then its an inventory item
               noninventory_item = !existing.expense_account.attributes.blank?
               if (sku_type == 'expense' && !noninventory_item) ||
                  (sku_type != 'expense' && noninventory_item)
                 # raise 'Item Update/create failed , inventory type mismatch fix in Netsuite'
               end
               if noninventory_item
                 find_noninvitem_by_id(existing.internal_id)
               else item = existing
               end
                end

      if !item.present?
        item = if sku_type == 'expense'
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
      else
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
      @sku ||= inventoryitem_payload['sku']
    end

    def sku_type
      @sku_type ||= inventoryitem_payload['sku_type']
    end

    def taxschedule
      @taxschedule ||= inventoryitem_payload['tax_type']
    end

    def dropship_account
      @dropship_account ||= inventoryitem_payload['dropship_account']
    end

    def description
      @description ||= inventoryitem_payload['name']
    end

    def ns_id
      @ns_id ||= inventoryitem_payload['ns_id']
    end

    def inventory_item_service
      @inventory_item_service ||= NetsuiteIntegration::Services::InventoryItem
                                  .new(@config)
    end

    def find_invitem_by_id(ns_id)
      NetSuite::Records::InventoryItem.get(internal_id: ns_id)
      # Silence the error
      # We don't care that the record was not found
    rescue NetSuite::RecordNotFound
    end

    def find_noninvitem_by_id(ns_id)
      NetSuite::Records::NonInventoryResaleItem.get(internal_id: ns_id)
      # Silence the error
      # We don't care that the record was not found
    rescue NetSuite::RecordNotFound
    end
  end
end
