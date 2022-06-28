module NetsuiteIntegration
  class MaintainSupplier < Base
    attr_reader :config, :payload, :vendor_payload

    def initialize(config, payload = {})
      super(config, payload)
      @config = config

      @vendor_payload = payload[:supplier]

      vendor =  find_by_ext_id(id) || find_by_name(company_name)

      if vendor.blank?
        vendor = NetSuite::Records::Vendor.new(
          company_name: vendor_payload['company_name'],
          entityid: vendor_payload['company_name'],
          external_id: id,
          email: vendor_payload['email'],
          first_name: vendor_payload['first_name'],
          category: {internal_id: vendor_payload['vendor_category']},
          last_name: vendor_payload['last_name'],
          billaddr1: vendor_payload['address1'],
          billaddr2: vendor_payload['address2'],
          billcity: vendor_payload['city'],
          billstate: vendor_payload['state'],
          billzip: vendor_payload['zipcode'],
          billcountry: vendor_payload['country'],
          phone: vendor_payload['phone']
        )
        vendor.add
      else
        #do not change address,category as ap may have overwritten it
        vendor.update(
          company_name: company_name,
          entityid: company_name,
          external_id: id
        )
      end

      if vendor.errors.any? { |e| e.type != 'WARN' }
          raise "Vendor Update/create failed: #{vendor.errors.map(&:message)}"
      else
        xdata = { company_name: company_name, netsuite_id: vendor.internal_id }
        ExternalReference.record :supplier, company_name, { netsuite: xdata },
                                 netsuite_id: vendor.internal_id
      end
    end

    def id
      @id = vendor_payload['id']
    end

    def company_name
      @company_name = vendor_payload['company_name']
    end

    def ns_id
      @ns_id = vendor_payload['ns_id']
    end

    def find_by_id(id)
      NetSuite::Records::Vendor.get(internal_id: id)
      # Silence the error
      # We don't care that the record was not found
    rescue NetSuite::RecordNotFound
    end

    def find_by_ext_id(id)
      NetSuite::Records::Vendor.get(external_id: id)
      # Silence the error
      # We don't care that the record was not found
    rescue NetSuite::RecordNotFound
    end

    def find_by_name(name)
      NetSuite::Records::Vendor.search(criteria: {
                                         basic: [{
                                           field: 'entityId',
                                           value: name,
                                           operator: 'startswith'
                                         }]
                                       }).results.first
    end
  end
end