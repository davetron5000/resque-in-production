class UsersController
  def create
    user = User.new(params[:user])
    if user.save
      Resque.enqueue(UserWelcomeMailerJob,user.id)
    else
      render 'new'
    end
  end
end
