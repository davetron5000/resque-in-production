class PurchasesController
  def create
    customer = current_customer
    purchase = Purchase.new(params[:purchase].merge(customer: customer))
    if purchase.valid?
      Purchase.transaction do
        customer.last_order_date = Time.now
        purchase.save!
        customer.save!
        Resque.enqueue(ConfirmPurhaseMailerJob,purchase.id)
      end
    else
      render 'new'
    end
  end
end
