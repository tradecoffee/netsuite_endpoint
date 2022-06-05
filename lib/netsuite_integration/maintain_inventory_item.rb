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

    def sku_needs_upd(line_item)
      ref = ExternalReference.products.find_by_external_id(solidus_id: line_item['id'].to_i)
                             .try!(:object)
      sku_needs_upd = if ref.nil? ||
                         ref['netsuite'].nil? ||
                         ref['netsuite']['sku'] != line_item['sku'] ||
                         ref['netsuite']['description'] != line_item['name']
                        true
                      else false
                      end
    end

    def add_sku(line_item)
      # exit out prevent netsuite calls as it .... they are to expensive!
      # return unless sku_needs_upd(line_item)

      sku = line_item['sku']
      expense_sku = line_item['sku_type'] == 'expense'
      taxschedule = line_item['tax_type']
      dropship_account = line_item['dropship_account']
      description = line_item['name']
      ns_id = line_item['ns_id']

      # always find sku
      item = inventory_item_service.find_by_item_name(sku)

      if item.present?
        # ignore updates
        return
      end

      # exit if no changes limit tye amout of nestuite calls/changes
      stock_desc = description.rstrip[0, 21]

      if item.present? && expense_sku &&
         item.record_type.equal?('InventoryItem')
        raise 'Item Update/create failed v1 , inventory type mismatch fix in Netsuite'
      end

      if item.present?
        item = if expense_sku
                 NetSuite::Records::NonInventoryResaleItem.new(
                   item_id: sku,
                   external_id: sku,
                   tax_schedule: { internal_id: taxschedule },
                   expense_account: { internal_id: dropship_account },
                   vendor_name: description[0, 60],
                   purchase_description: description
                 )
               else
                 NetSuite::Records::InventoryItem.new(
                   item_id: sku,
                   external_id: ext_id,
                   tax_schedule: { internal_id: taxschedule },
                   vendor_name: description[0, 60],
                   purchase_description: description
                 )
               end
        item.add
      end


      if item.errors.present? { |e| e.type != 'WARN' }
        raise "Item Update/create failed v1: #{item.errors.map(&:message)}"
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