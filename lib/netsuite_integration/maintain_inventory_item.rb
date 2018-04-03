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

    def add_sku(line_item)
      sku=line_item['sku']
      expense_sku = line_item['sku_type'] == 'expense'
      taxschedule=line_item['tax_type']
      dropship_account=line_item['dropship_account']
      description=line_item['name']
      ns_id=line_item['ns_id']

      # awlays keep external_id in numeric format
      ext_id = if sku.is_a? Numeric
                 sku.to_i
               else
                 sku
               end

      # always find sku using internal id incase of sku rename
      item = if !ns_id.nil?
               inventory_item_service.find_by_internal_id(ns_id)
             else
               inventory_item_service.find_by_item_id(sku)
             end

      # exit if no changes limit tye amout of nestuite calls/changes
      stock_desc=description.rstrip[0,21]

      if item.present?
        # if expense account is blank then its an inventory item
        if expense_sku &&
           item.record_type.equal?('InventoryItem')
          raise 'Item Update/create failed , inventory type mismatch fix in Netsuite'
        end
      end

      if !item.present?
        item = if expense_sku
                 NetSuite::Records::NonInventoryResaleItem.new(
                   item_id: sku,
                   external_id: ext_id,
                   tax_schedule: { internal_id: taxschedule },
                   expense_account: { internal_id: dropship_account },
                   upc_code: sku,
                   vendor_name: description[0, 60],
                   purchase_description: description,
                   stock_description: stock_desc
                 )
               else
                 NetSuite::Records::InventoryItem.new(
                   item_id: sku,
                   external_id: ext_id,
                   tax_schedule: { internal_id: taxschedule },
                   upc_code: sku,
                   vendor_name: description[0, 60],
                   purchase_description: description,
                   stock_description: stock_desc
                 )
               end
        item.add
      elsif item.present? &&
            (stock_desc!=item.stock_description ||
            sku!=item.item_id ||
            ns_id!=item.internal_id )
            if item.record_type.equal?('NonInventorySaleItem')
              item.update(
                item_id: sku,
                external_id: ext_id,
                tax_schedule: { internal_id: taxschedule },
                expense_account: { internal_id: dropship_account },
                upc_code: sku,
                vendor_name: description[0, 60],
                purchase_description: description,
                stock_description: stock_desc
              )
            elsif item.record_type.equal?('InventoryItem')
              item.update(
                item_id: sku,
                external_id: ext_id,
                tax_schedule: { internal_id: taxschedule },
                upc_code: sku,
                vendor_name: description[0, 60],
                purchase_description: description,
                stock_description: stock_desc
              )
            end
    end

      if item.errors.present? { |e| e.type != 'WARN' }
        raise "Item Update/create failed: #{item.errors.map(&:message)}"
      else
        line_item = { sku: sku, netsuite_id: item.internal_id,
                      description: description }
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
