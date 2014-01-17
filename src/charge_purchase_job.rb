class PurchaseChargeJob
  @queue = :purchasing
  def self.perform(purchase_id)
    purchase = Purchase.find(purchase_id)
    purchase.capture_authorization!
    purchase.generate_pack_in_materials!
  end
end
