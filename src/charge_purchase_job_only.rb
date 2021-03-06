class PurchaseChargeJob
  @queue = :purchasing
  def self.perform(purchase_id)
    purchase = Purchase.find(purchase_id)
    purchase.capture_authorization!
    Resque.enqueue(PackInMaterialsJob,purchase.id)
  end
end
