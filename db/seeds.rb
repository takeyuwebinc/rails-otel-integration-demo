books_data = [
  { title: "プログラミングRuby", author: "Dave Thomas", price: 4800, stock: 15 },
  { title: "リファクタリング", author: "Martin Fowler", price: 4200, stock: 8 },
  { title: "達人プログラマー", author: "David Thomas", price: 3600, stock: 3 },
  { title: "Clean Code", author: "Robert C. Martin", price: 3800, stock: 20 },
  { title: "Design Patterns", author: "GoF", price: 5200, stock: 0 }
]

books_data.each do |attrs|
  Book.find_or_create_by!(title: attrs[:title]) do |book|
    book.assign_attributes(attrs)
  end
end

puts "Created #{Book.count} books"
