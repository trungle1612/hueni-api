require "test_helper"

class WebPushTest < ActiveSupport::TestCase
  # A P-256 key from its raw private scalar and public point (the RFC's test keys).
  def ec_key(private_b64, public_b64)
    der = OpenSSL::ASN1::Sequence([ OpenSSL::ASN1::Integer(1), OpenSSL::ASN1::OctetString(WebPush.decode(private_b64)),
      OpenSSL::ASN1::ObjectId("prime256v1", 0, :EXPLICIT), OpenSSL::ASN1::BitString(WebPush.decode(public_b64), 1, :EXPLICIT) ]).to_der
    OpenSSL::PKey::EC.new(der)
  end

  test "encrypts as in RFC 8291 appendix A" do
    as_key = ec_key("yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw", "BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8")
    body = WebPush.encrypt("When I grow up, I want to be a watermelon",
      WebPush.decode("BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4"),
      WebPush.decode("BTBZMqHH6r4Tts7J_aSIgg"), salt: WebPush.decode("DGv6ra1nlYgDCS1FRnbzlw"), as_key:)

    assert_equal "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN",
      WebPush.encode(body)
  end
end
