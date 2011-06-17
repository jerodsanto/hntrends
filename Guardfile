guard "sass", output: "public" do
  watch(%r{^public/.+\.s[ac]ss})
end

guard "coffeescript", output: "." do
  watch("server.coffee")
end
guard "coffeescript", output: "public" do
  watch("client.coffee")
end
