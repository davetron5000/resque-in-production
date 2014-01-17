class PackInMaterialsJob 
  extend Resque::Plugins::Retry
  @queue = :purchasing
  @retry_limit = 5
  @retry_delay = 90 #seconds

  def self.perform(purchase_id)
    purchase = Purchase.find(purchase_id)
    purchase.generate_pack_in_materials!
  end
end
