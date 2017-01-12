module NetsuiteIntegration
  class PurchaseOrder
    attr_reader :config

    def initialize(config)
      @config = config
    end

    def messages
      @messages ||= purchase_orders
    end

    def last_modified_date
      collection.last.last_modified_date.utc + 1.second
    end

    def collection
      @collection ||= Services::PurchaseOrder.new(@config).latest
    end

    def purchase_orders
      collection.map do |po|
        {
          id: po.tran_id,
          name: po.memo,
          due_date: po.due_date,
          alt_po_number: po.internal_id,
          status: po.status,
          location: {
            name: po.location.attributes[:name],
            external_id: po.location.external_id,
            internal_id: po.location.internal_id
          },
          vendor: {
            name: po.entity.attributes[:name],
            external_id: po.entity.external_id,
            internal_id: po.entity.internal_id
          },
          line_items: items(po),
          channel: 'NetSuite'
        }
      end
    end

    def items(po)
      po.item_list.items.each_with_index.map do |item, index|
        {
          itemno: item.item.attributes[:name],
          description: item.description,
          quantity: item.quantity,
          unit_price: item.rate,
          vendor: {
            name: item.vendor_name
          },
          location: {
            name: item.location.attributes[:name]
          }
        }
      end
    end
  end
end
