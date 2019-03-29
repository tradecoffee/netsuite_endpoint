# frozen_string_literal: true

module NetsuiteIntegration
  class VendorBill < Base
    attr_reader :config, :payload,  :bill_payload, :bill

    def initialize(config, payload = {})
      super(config, payload)
      @config = config
      @bill_payload = payload[:vendor_bill]
      create_bill
    end

    def new_bill?
      new_bill ||= !find_bill_by_external_id(bill_id)
    end

    def find_bill_by_external_id(bill_id)
      NetSuite::Records::VendorBill.get(external_id: bill_id)
      # Silence the error
      # We don't care that the record was not found
    rescue NetSuite::RecordNotFound
    end

    def bill_id
      bill_payload['bill_id']
    end


    def bill_date
      bill_payload['bill_date']
    end

    def bill_dept
      bill_payload['bill_dept']
    end

    def bill_ap_acct
      bill_payload['bill_ap_acct']
    end

    def bill_type
      bill_payload['bill_type']
    end

    def bill_init_status
      bill_payload['bill_init_status']
    end

    def bill_memo
      bill_payload['bill_memo']
    end

    def bill_vendor_name
      bill_payload['bill_vendor_name']
    end

    def bill_vendor_id
      bill_payload['bill_vendor_id']
    end

    def bill_location
      bill_payload['bill_location']
    end

    def build_item_list
      line = 0
      bill_items = bill_payload[:line_items].map do |item|
        # do not process zero qty bills
        next unless item[:quantity].to_i != 0
        line += 1
        nsproduct_id = item[:nsproduct_id]
          if nsproduct_id.nil?
            # fix correct reference else abort if sku not found!
            sku = item[:sku]
            invitem = inventory_item_service.find_by_item_id(sku)
              if invitem.present?
                nsproduct_id = invitem.internal_id
                line_obj = { sku: sku, netsuite_id: invitem.internal_id,
                            description: invitem.purchase_description }
                ExternalReference.record :product, sku, { netsuite: line_obj },
                                        netsuite_id: invitem.internal_id
              else
                raise "Error Item/sku missing in Netsuite, please add #{sku}!!"
              end
          else
            invitem = NetSuite::Records::InventoryItem.get(nsproduct_id)
          end

          NetSuite::Records::VendorBillItem.new(item: { internal_id: nsproduct_id },
                                                              line: line,
                                                              rate: item[:cost]&.to_f,
                                                              quantity: item[:quantity]&.to_i,
                                                              department: {internal_id: bill_dept},
                                                              location: { internal_id: bill_location })

        end
        #merge Items
      NetSuite::Records::VendorBillItemList.new(replace_all: true,item: bill_items.compact)
    end

    def inventory_item_service
      @inventory_item_service ||= NetsuiteIntegration::Services::InventoryItem.new(@config)
    end

    def create_bill
      if new_bill?
        # internal numbers differ between platforms

        if !bill_vendor_id.nil?
            vendor_id = bill_vendor_id
        else
            vendor = find_vendor_by_name(bill_vendor_name)
            if vendor.nil?
              raise "Vendor : #{bill_vendor_name} not found!"
            else
              vendor_id = vendor.internal_id
            end
        end

        @bill = NetSuite::Records::VendorBill.new
        bill.external_id = bill_id
        bill.memo = bill_memo
        bill.account = { internal_id: bill_ap_acct }
        bill.tran_id = bill_id
        bill.approval_status= { internal_id: bill_init_status}
        bill.entity = { internal_id: vendor_id }
        bill.tran_date = bill_date
        bill.item_list = build_item_list
        if bill_type == 'DS-CC'
          bill_type_id = 2
        else
          bill_type_id = 1
        end
        bill.custom_field_list.custbodyinvoice_type={:name=>bill_type,:internal_id=>bill_type_id,:type_id=>134}

          # we can sometimes receive bills were everything is zero!
        if bill.item_list.item.present?
          bill.add
          if bill.errors.any? { |e| e.type != 'WARN' }
            raise "bill create failed: #{bill.errors.map(&:message)}"
          else
            line_item = { bill_id: bill_id,
                          netsuite_id: bill.internal_id,
                          description: bill_memo,
                          type: 'vendor_bill' }

              ExternalReference.record :vendor_bill,
                                       bill_id,
                                       { netsuite: line_item },
                                       netsuite_id: bill.internal_id

          end
        end
      end
    end

    def find_vendor_by_name(name)
      NetSuite::Records::Vendor.search(criteria: {
                                         basic: [{
                                           field: 'entityId',
                                           value: name,
                                           operator: 'contains'
                                         }]
                                       }).results.first
    end
 end
end