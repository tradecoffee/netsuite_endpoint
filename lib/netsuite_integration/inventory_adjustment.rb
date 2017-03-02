module NetsuiteIntegration
  class InventoryAdjustment < Base
    attr_reader :config, :payload, :ns_adjustment,:adjustment_payload,:adjustment

    def initialize(config, payload = {})
        super(config, payload)
        @config = config
        if transfer_order?
            @adjustment_payload=payload[:transfer_order] 
        else 
            @adjustment_payload=payload[:inventory_adjustment]  
        end

        if adjustment_location.nil?
            raise "Location Missing!! Sync vend & netsuite outlets"
        end

        create_adjustment
      
    end

    def new_adjustment?
        new_adjustment ||= !find_adjustment_by_external_id(adjustment_id) 
    end
  
    def ns_adjustment
        @ns_adjustment ||= NetSuite::Records::InventoryAdjustment.get(ns_id)
    end

    def find_adjustment_by_external_id(adjustment_id)
        
        NetSuite::Records::InventoryAdjustment.get(external_id: adjustment_id)
        # Silence the error
        # We don't care that the record was not found
        rescue NetSuite::RecordNotFound
    end
 
    def transfer_order?
        payload[:transfer_order].present?
    end

    def adjustment_id
        @adjustment_id  ||=adjustment_payload['adjustment_id']
    end
    
    def ns_id
        @ns_id ||=adjustment_payload['id']
    end

    def adjustment_date
        @adjustment_date ||=adjustment_payload['adjustment_date']
    end    
  
    def adjustment_account_number
        @adjustment_account_number ||=adjustment_payload['adjustment_account_number']
    end
     
    def adjustment_memo
        @adjustment_memo ||=adjustment_payload['adjustment_memo']
    end

    def adjustment_location
        @adjustment_location ||=adjustment_payload['location']
    end

    
    def build_item_list
       line=0   
       adjustment_items = adjustment_payload[:line_items].map do |item| 
            #do not process zero qty adjustments
            if  item[:adjustment_qty].to_i != 0
                line += 1
                nsproduct_id=item[:nsproduct_id]
                if nsproduct_id.nil?
                   #fix correct reference else abort if sku not found!
                   sku=item[:sku]
                   invitem = inventory_item_service.find_by_item_id(sku)
                   if invitem.present?
                        nsproduct_id=invitem.internal_id
                        line_obj = { sku: sku, netsuite_id: invitem.internal_id, description: invitem.purchase_description }
                        ExternalReference.record :product, sku, { netsuite: line_obj }, netsuite_id: invitem.internal_id
                    else 
                        raise "Error Item/sku missing in Netsuite, please add #{sku}!!"                     
                    end
                else 
                  invitem = NetSuite::Records::InventoryItem.get(nsproduct_id)  
                end
                #rework for performance at somepoint no need to get inv item if qty <0
                #check average price and fill it in ..ns has habit of Zeroing it out when u hit zero quantity
                 itemlocation=invitem.locations_list.locations.select {|e|  e[:location_id][:@internal_id]==adjustment_location}.first                   
                 if itemlocation[:average_cost_mli].to_i == 0 && item[:adjustment_qty].to_i>0
                    #can only set unit price on takeon
                        case 
                                when itemlocation[:last_purchase_price_mli].to_i != 0
                                    unit_cost=itemlocation[:last_purchase_price_mli]
                                when invitem.last_purchase_price.to_i != 0
                                    unit_cost=invitem.last_purchase_price
                                when item[:cost].present?
                                    unit_cost=item[:cost]
                        end
                        #set default unit_price if none
                        NetSuite::Records::InventoryAdjustmentInventory.new({
                            item: { internal_id: nsproduct_id },
                            quantity: item[:received],
                            line: line,
                            unit_cost: unit_cost.to_i,
                            adjust_qty_by: item[:adjustment_qty],
                            location: {internal_id: adjustment_location}               
                        })
                else
                    NetSuite::Records::InventoryAdjustmentInventory.new({
                        item: { internal_id: nsproduct_id },
                        quantity: item[:received],
                        line: line,
                        adjust_qty_by: item[:adjustment_qty],
                        location: {internal_id: adjustment_location}               
                    })
                end
            end
       end
          NetSuite::Records::InventoryAdjustmentInventoryList.new(replace_all: true, inventory: adjustment_items.compact)
       
    end

    def inventory_item_service
        @inventory_item_service ||= NetsuiteIntegration::Services::InventoryItem.new(@config)
    end
  
    def create_adjustment
        if new_adjustment?
            #internal numbers differ between platforms
            adjustment_account=find_by_account_number(adjustment_account_number)
            if adjustment_account.nil?
                raise raise "GL Account: #{adjustment_account_number} not found!"
            else
                adjustment_account_id=adjustment_account.internal_id
            end

            @adjustment=NetSuite::Records::InventoryAdjustment.new
            adjustment.external_id=adjustment_id 
            adjustment.memo=adjustment_memo
            adjustment.tran_date=adjustment_date.to_datetime
            adjustment.account={internal_id: adjustment_account_id}
            adjustment.adj_location={internal_id: adjustment_location}
            location={internal_id: adjustment_location}
            adjustment.inventory_list=build_item_list
            #we can sometime receive adjustments were everything i zero!
            if adjustment.inventory_list.inventory.present?
                adjustment.add
                if adjustment.errors.any?{|e| "WARN" != e.type}
                    raise "Adjustment create failed: #{adjustment.errors.map(&:message)}"
                else
                    line_item = { adjustment_id: adjustment_id, netsuite_id: adjustment.internal_id, description: adjustment_memo }
                    if transfer_order?
                        ExternalReference.record :transfer_order, adjustment_id, { netsuite: line_item }, netsuite_id: adjustment.internal_id
                    else
                        ExternalReference.record :inventory_adjustment, adjustment_id, { netsuite: line_item }, netsuite_id: adjustment.internal_id
                    end          
                end
            end                                     
        else             
            #raise "Warning : Duplicate adjustment EXT Id: \"#{adjustment_id}\" "        
        end
    end

    def find_by_account_number(account_number)
        NetSuite::Records::Account.search({ criteria: { basic: [{field: 'number',value: account_number,operator: 'is' }]}}).results.first
    end
 
 end
end