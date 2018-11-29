require "spec_helper"

require "fixtures/pirates"

RSpec.describe FmData::Spyke::Model::Orm do
  describe "#save" do
    let(:ship) { Ship.new }

    before do
      stub_session_login
    end

    context "with failed validations" do
      before do
        allow(ship).to receive(:valid?).and_return(false)

        stub_request(:post, fm_url(layout: "Ships") + "/records").to_return_fm({ recordId: 1, modId: 1 })
      end

      it "returns false when called with no options" do
        expect(ship.save).to eq(false)
      end

      it "returns true if successfully saved when called with validate: false" do
        expect(ship.save(validate: false)).to eq(true)
      end
    end

    context "with passing validations" do
      before do
        allow(ship).to receive(:valid?).and_return(true)
      end

      context "when the server responds successfully" do
        before do
          stub_request(:post, fm_url(layout: "Ships") + "/records").to_return_fm({ recordId: 1, modId: 1 })
        end

        it "returns true" do
          expect(ship.save).to eq(true)
        end
      end

      context "when the server responds with failure" do
        before do
          stub_request(:post, fm_url(layout: "Ships") + "/records").to_return_fm(false)
        end

        it "returns false" do
          expect(ship.save).to eq(false)
        end
      end
    end
  end

  describe ".all" do
    xit "returns a FmData::Spyke::Relation"
  end

  describe ".fetch" do
    context "when a query is present in current scope" do
      xit "applies limit JSON param"
      xit "applies offset JSON param"
      xit "applies sort JSON param"
      xit "applies query JSON param"
    end

    context "when no query is present in current scope" do
      xit "applies _limit URI param"
      xit "applies _offset URI param"
      xit "applies _sort URI param"
    end
  end
end

