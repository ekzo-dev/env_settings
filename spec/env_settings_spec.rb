# frozen_string_literal: true

RSpec.describe EnvSettings do
  it "has a version number" do
    expect(EnvSettings::VERSION).not_to be nil
  end

  it "provides Base class for inheritance" do
    expect(EnvSettings::Base).to be_a(Class)
  end
end
