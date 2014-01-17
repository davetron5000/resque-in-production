class UsersController
  def create
    user = User.new(params[:user])
    if user.save
      UserMailer.welcome(user).deliver
    else
      render 'new'
    end
  end
end
