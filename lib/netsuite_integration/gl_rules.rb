module NetsuiteIntegration
  class TransactionJournals < Base

    def self.generate(type,line)
        rules=TransactionCode[type.to_sym]
        if rules.nil?
            raise "rules not setup for journal type #{type}"
        end
        @journal = rules.map { |j| j.journallines(line)}.compact
    end
  end

  class TransactionCode < Base
    Transaction = Struct.new(:amtcol,:debit_acct, :credit_acct, :debit_dept, :credit_dept, :memo, :debit_lob, :credit_lob) do
      def journallines(line)
          @journal_items=[]
            amount=line[amtcol]&.round(2)
            if amount.to_f != 0 && !amount.nil?
                location=line['location']
                memo=line['memo'].to_s+'-'+amtcol.to_s

                ####### debit journal ############

                acct = debit_acct.dig(:val)
                if acct.nil?
                   map=debit_acct.dig(:map)
                   acct=fieldmap(map,line,'acct')
                end

                dept = debit_dept.dig(:val)
                if dept.nil?
                   map=debit_dept.dig(:map)
                   dept=fieldmap(map,line,'dept')
                end

                classification = debit_lob.dig(:val)
                if classification.nil?
                   map = debit_lob.dig(:map)
                   classification = fieldmap(map,line,'lob')
                end

                @journal_items << NetSuite::Records::JournalEntryLine.new({
                    account: { internal_id: acct },
                    department: if !dept.nil? then { internal_id: dept } else nil end,
                    debit: if amount > 0 then amount.abs else 0 end,
                    credit: if amount < 0 then amount.abs else 0 end,
                    memo: memo,
                    location: {internal_id: location},
                    class: {internal_id: classification}
                })

                ######  credit journal #########
                acct = credit_acct.dig(:val)

                if acct.nil?
                   map=credit_acct.dig(:map)
                   acct=fieldmap(map,line,'acct')
                end

                dept = credit_dept.dig(:val)
                if dept.nil?
                   map=credit_dept.dig(:map)
                   dept=fieldmap(map,line,'dept')
                end

                classification = credit_lob.dig(:val)
                  if classification.nil?
                     map = credit_lob.dig(:map)
                     classification = fieldmap(map,line,'lob')
                  end

                amount*=-1

                @journal_items << NetSuite::Records::JournalEntryLine.new({
                      account: { internal_id: acct },
                      department: if !dept.nil? then { internal_id: dept } else nil end,
                      debit: if amount > 0 then amount.abs else 0 end,
                      credit: if amount < 0 then amount.abs else 0 end,
                      memo: memo,
                      location: {internal_id: location},
                      class: {internal_id: classification}
                  })
            end
        end

      def fieldmap(map,line,field)
        if !map.nil?
          if !line[map].nil?
              lookup=TransactionLookupMap[(map.to_s+'_'+line[map].downcase.gsub(" ",'')).to_sym]
          end
        end

         if lookup.nil?
            lookup=TransactionLookupMap[(map.to_s+'_default').to_sym]
            if lookup.nil?
               raise "no data in record to map for field #{map.to_s+'_default'}"
            end
         end

        lookup.first[field]
      end

    end

    def self.[](key)
      transactions[key]
    end

    def self.transactions
      @transactions ||= {}
    end

    def self.add(key, amtcol:,debit_acct:, credit_acct: ,debit_dept: ,credit_dept: , memo:, debit_lob:, credit_lob:)
      transactions[key] ||= []
      transactions[key] << Transaction.new(amtcol, debit_acct, credit_acct, debit_dept, credit_dept, memo, debit_lob, credit_lob)
    end
end

class TransactionLookupMap < Base
    Lookupmap = Struct.new(:acct, :dept, :lob)

    def self.[](key)
      lookupmaps[key]
    end

    def self.lookupmaps
      @lookupmaps ||= {}
    end

    def self.add(key, acct:, dept:, lob:)
        lookupmaps[key] ||= []
        lookupmaps[key] << Lookupmap.new(acct, dept, lob)
    end

  end
end