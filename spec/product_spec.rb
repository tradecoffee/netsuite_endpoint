require 'spec_helper'

describe Product do
  include_examples "config hash"

  subject do
    VCR.use_cassette("inventory_item/get") do
      described_class.new config
    end
  end

  it "returns parameters with last_modified_date value" do
    collection = subject.collection
    parameters = subject.parameters[:parameters]
    expect(parameters.first[:value]).to eq collection.last.last_modified_date
  end

  it "maps parameteres according to current product schema" do
    mapped_product = subject.messages.first[:payload][:product]
    item = subject.collection.first

    expect(mapped_product[:name]).to eq item.store_display_name
    expect(mapped_product[:sku]).to eq item.item_id
    expect(mapped_product[:price]).to eq item.cost
  end
end
