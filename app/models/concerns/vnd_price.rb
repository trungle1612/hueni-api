# Whole-VND price columns (rooms and their bookings' quotes) typed by owners.
module VndPrice
  extend ActiveSupport::Concern

  UNITS = { "k" => 1_000, "nghìn" => 1_000, "ngàn" => 1_000, "tr" => 1_000_000, "triệu" => 1_000_000 }.freeze

  # Owners type prices like "450.000", "450 000 ₫", "450k" or "1,2tr": drop thousands separators and the
  # currency mark so "." isn't read as a decimal point; a unit multiplies. Anything else is left for validation to reject.
  def self.parse(value)
    return value unless value.is_a?(String)
    amount, unit = value.downcase.delete(" ").match(/\A(\d+(?:[.,]\d+)?)(#{UNITS.keys.join("|")})\z/)&.captures
    unit ? (BigDecimal(amount.tr(",", ".")) * UNITS[unit]).to_i : value.gsub(/vn[dđ]|[.,\s₫đ]/i, "").presence
  end

  class_methods do
    def vnd_price(*names)
      names.each do |name|
        define_method(:"#{name}=") { |value| super(VndPrice.parse(value)) }
        validates name, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
      end
    end
  end
end
