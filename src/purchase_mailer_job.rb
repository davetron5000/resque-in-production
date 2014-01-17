class ConfirmPurhaseMailerJob
  @queue = :mail
  def self.perform(purchase_id)
    purchase = Purchase.find(purchase_id)
    PurchaseMailer.confirm_purchase(purchase).deliver
  end
end
