module NetsuiteIntegration
  module Services
    # Make sure "Sell Downloadble Files" is enabled in your NetSuite account
    # otherwise search won't work
    #
    # In order to retrieve a Matrix Item you also need to enable "Matrix Items"
    # in your Company settings
    #
    # Specify Item type because +search+ maps to NetSuite ItemSearch object
    # which will bring all kinds of items and not only inventory items
    #
    # Records need to be ordered by lastModifiedDate programatically since
    # NetSuite api doesn't allow us to do that on the request. That's the
    # reason the search lets the page size default of 1000 records. We'd better
    # catch all items at once and sort by date properly or we might end up
    # losing data
    class InventoryItem < Base
      def latest
        ignore_future.sort_by { |c| c.last_modified_date.utc }
      end

      def find_by_name(name)
        NetSuite::Records::InventoryItem.search({
          criteria: {
            basic: [{
              field: 'displayName',
              value: name,
              operator: 'contains'
            }]
          }
        }).results.first
      end

      def find_by_item_id(item_id)
        NetSuite::Records::InventoryItem.search({
          criteria: {
            basic: [
              {
                field: 'itemId',
                value: item_id,
                operator: 'is'
              },
              {
                field: 'type',
                operator: 'anyOf',
                type: 'SearchEnumMultiSelectField',
                value: ['_inventoryItem']
              },
            ]
          },
          preferences: {
            bodyFieldsOnly: false
          }
        }).results.first
      end

      private
        # We need to set bodyFieldsOnly false to grab the pricing matrix
        def search
          NetSuite::Records::InventoryItem.search({
            criteria: {
              basic: [
                {
                  field: 'lastModifiedDate',
                  type: 'SearchDateField',
                  operator: 'within',
                  value: [
                    last_updated_after,
                    time_now.iso8601
                  ]
                },
                {
                  field: 'type',
                  operator: 'anyOf',
                  type: 'SearchEnumMultiSelectField',
                  value: ['_inventoryItem']
                },
                {
                  field: 'isInactive',
                  value: false
                }
              ]
            },
            preferences: {
              pageSize: 100,
              bodyFieldsOnly: false
            }
          }).results
        end

        def ignore_future
          search.select do |item|
            item.last_modified_date.utc <= time_now
          end
        end

        # Help us mock this when running the specs. Otherwise we might get VCR
        # as different request might be done depending on this timestamp
        def time_now
          Time.now.utc
        end

        def last_updated_after
          Time.parse(config.fetch('netsuite_last_updated_after')).iso8601
        end
    end
  end
end
