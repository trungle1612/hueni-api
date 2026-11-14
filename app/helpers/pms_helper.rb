module PmsHelper
  # "T4, 21/10/2026", as in the design's top bar.
  def pms_day(date) = "#{%w[CN T2 T3 T4 T5 T6 T7][date.wday]}, #{date.strftime("%d/%m/%Y")}"
end
