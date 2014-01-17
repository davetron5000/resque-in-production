class PackInMaterialsJob 
  @queue = :purchasing
  def self.perform(purchase_id)
    purchase = Purchase.find(purchase_id)
    purchase.generate_pack_in_materials!
  end
end
