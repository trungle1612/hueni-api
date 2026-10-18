require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "phone formats mobiles, including +84 ones, and leaves anything else as given" do
    assert_equal "0912 345 678", phone("0912345678")
    assert_equal "0912 345 678", phone("+84 912 345 678")
    assert_equal "0234 3 812 345", phone("0234 3 812 345")
    assert_equal "", phone(nil)
  end
end
