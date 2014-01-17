class PurchaseChargeJob
  @queue = :purchasing
  def self.perform(purchase_id)
    purchase = Purchase.find(purchase_id)
    purchase.capture_authorization! unless purchase.captured?
    Resque.enqueue(PackInMaterialsJob,purchase.id)
  end
end
